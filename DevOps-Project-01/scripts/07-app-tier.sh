#!/bin/bash
# 07-app-tier.sh (rebuild — dynamic bucket name, idempotent IAM, DB_PASSWORD
# baked into a generated userdata file, minimal ASG sizing)
set -e

source ./secondary-vpc.env
source ./security-groups.env

WAR_PATH="../Java-Login-App/target/dptweb-1.0.war"
if [ ! -f "$WAR_PATH" ]; then
  echo "ERROR: $WAR_PATH not found. Build it first with: cd ../Java-Login-App && mvn clean package"
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="devopsproject01-artifacts-$ACCOUNT_ID"

# --- S3 bucket for the WAR file ---
if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Bucket $BUCKET_NAME already exists, reusing."
else
  aws s3 mb s3://$BUCKET_NAME
  echo "Created bucket $BUCKET_NAME"
fi
aws s3 cp "$WAR_PATH" s3://$BUCKET_NAME/dptweb-1.0.war
echo "Uploaded WAR to s3://$BUCKET_NAME/dptweb-1.0.war"

# --- IAM role: S3 read (scoped to this bucket only) + SSM — idempotent ---
if aws iam get-role --role-name TomcatS3Role >/dev/null 2>&1; then
  echo "Role TomcatS3Role already exists, reusing."
else
  aws iam create-role --role-name TomcatS3Role --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }' > /dev/null
  aws iam attach-role-policy --role-name TomcatS3Role \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  echo "Created role TomcatS3Role"
fi

# Always refresh the inline policy so it points at THIS run's bucket
aws iam put-role-policy --role-name TomcatS3Role --policy-name S3ReadArtifacts --policy-document "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{\"Effect\": \"Allow\", \"Action\": [\"s3:GetObject\"], \"Resource\": \"arn:aws:s3:::$BUCKET_NAME/*\"}]
}"

if aws iam get-instance-profile --instance-profile-name TomcatS3Profile >/dev/null 2>&1; then
  echo "Instance profile TomcatS3Profile already exists, reusing."
else
  aws iam create-instance-profile --instance-profile-name TomcatS3Profile > /dev/null
  aws iam add-role-to-instance-profile --instance-profile-name TomcatS3Profile --role-name TomcatS3Role
  echo "Created instance profile TomcatS3Profile"
  echo "Waiting ~15s for IAM propagation..."
  sleep 15
fi

# --- Bake DB_PASSWORD + correct bucket name into a generated userdata file ---
# (tomcat-userdata.sh as committed never exports DB_PASSWORD before starting
# Tomcat, and still points at the OLD bucket name — fixing both here.)
read -s -p "Re-enter the RDS master password (to bake into Tomcat's startup env): " DB_PASSWORD
echo

sed "s|s3://devopsproject01-artifacts-1787865399/dptweb-1.0.war|s3://$BUCKET_NAME/dptweb-1.0.war|" \
  tomcat-userdata.sh > tomcat-userdata-runtime.sh

# Insert the DB_PASSWORD export right before the Tomcat startup line
sed -i "s|^/opt/tomcat9/bin/startup.sh|export DB_PASSWORD='$DB_PASSWORD'\n/opt/tomcat9/bin/startup.sh|" \
  tomcat-userdata-runtime.sh

echo "Generated tomcat-userdata-runtime.sh (gitignore this — it contains the DB password in plaintext)"

AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text --region us-east-1)

USER_DATA_B64=$(base64 -w 0 tomcat-userdata-runtime.sh)

aws ec2 create-launch-template \
  --launch-template-name TomcatServerTemplate \
  --version-description TomcatVersion1 \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"SecurityGroupIds\": [\"$TOMCAT_SG\"],
    \"IamInstanceProfile\": {\"Name\": \"TomcatS3Profile\"},
    \"UserData\": \"$USER_DATA_B64\"
  }" > /dev/null
echo "Created launch template TomcatServerTemplate"

# --- Internal target group + internal NLB ---
TG_ARN=$(aws elbv2 create-target-group \
  --name TomcatTG --protocol TCP --port 8080 --vpc-id $SECONDARY_VPC_ID \
  --target-type instance --health-check-protocol TCP --health-check-port 8080 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

NLB_ARN=$(aws elbv2 create-load-balancer \
  --name InternalTomcatNLB --type network --scheme internal \
  --subnets $SECONDARY_PRIV_SUBNET_A $SECONDARY_PRIV_SUBNET_B \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

NLB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $NLB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "NLB_DNS=$NLB_DNS"

aws ec2 wait network-load-balancer-available --load-balancer-arns $NLB_ARN 2>/dev/null || true

aws elbv2 create-listener \
  --load-balancer-arn $NLB_ARN --protocol TCP --port 8080 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN > /dev/null

# --- ASG (minimal sizing: 1 instance, room to grow to 2) ---
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name TomcatASG \
  --launch-template LaunchTemplateName=TomcatServerTemplate,Version='$Latest' \
  --min-size 1 --max-size 2 --desired-capacity 1 \
  --vpc-zone-identifier "$SECONDARY_PRIV_SUBNET_A,$SECONDARY_PRIV_SUBNET_B" \
  --health-check-type EC2 --health-check-grace-period 300

aws autoscaling attach-load-balancer-target-groups \
  --auto-scaling-group-name TomcatASG \
  --target-group-arns $TG_ARN

echo "Created TomcatASG (min1/desired1/max2), attached to TomcatTG"

cat > app-tier.env <<EOF
export BUCKET_NAME=$BUCKET_NAME
export TOMCAT_TG_ARN=$TG_ARN
export INTERNAL_NLB_ARN=$NLB_ARN
export INTERNAL_NLB_DNS=$NLB_DNS
EOF
echo "Wrote app-tier.env"
echo ""
echo "IMPORTANT: INTERNAL_NLB_DNS=$NLB_DNS"
echo "This is what nginx-userdata.sh needs to point at before we run 06-frontend-tier.sh."
