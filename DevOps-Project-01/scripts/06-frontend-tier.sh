#!/bin/bash
# 06-frontend-tier.sh (rebuild — patches real Internal NLB DNS into nginx
# config, minimal ASG sizing)
set -e

source ./primary-vpc.env
source ./security-groups.env
source ./app-tier.env

# --- Patch the real Internal Tomcat NLB DNS name into nginx's upstream config ---
sed "s|InternalTomcatNLB-49c5132eae8ab1e2.elb.us-east-1.amazonaws.com|$INTERNAL_NLB_DNS|" \
  nginx-userdata.sh > nginx-userdata-runtime.sh
echo "Generated nginx-userdata-runtime.sh pointing at $INTERNAL_NLB_DNS"

AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text --region us-east-1)

USER_DATA_B64=$(base64 -w 0 nginx-userdata-runtime.sh)

aws ec2 create-launch-template \
  --launch-template-name WebServerTemplate \
  --version-description WebServerVersion1 \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"SecurityGroupIds\": [\"$FRONTEND_SG\"],
    \"UserData\": \"$USER_DATA_B64\"
  }" > /dev/null
echo "Created launch template WebServerTemplate"

TG_ARN=$(aws elbv2 create-target-group \
  --name WebServerTG --protocol TCP --port 80 --vpc-id $PRIMARY_VPC_ID \
  --target-type instance --health-check-protocol TCP --health-check-port 80 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

NLB_ARN=$(aws elbv2 create-load-balancer \
  --name PublicNLB --type network --scheme internet-facing \
  --subnets $PRIMARY_PUB_SUBNET_A $PRIMARY_PUB_SUBNET_B \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

NLB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $NLB_ARN \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "PUBLIC_NLB_DNS=$NLB_DNS"

aws elbv2 create-listener \
  --load-balancer-arn $NLB_ARN --protocol TCP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN > /dev/null

# --- ASG (minimal sizing: 1 instance, room to grow to 2) ---
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name WebServerASG \
  --launch-template LaunchTemplateName=WebServerTemplate,Version='$Latest' \
  --min-size 1 --max-size 2 --desired-capacity 1 \
  --vpc-zone-identifier "$PRIMARY_PRIV_SUBNET_A,$PRIMARY_PRIV_SUBNET_B" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB --health-check-grace-period 300

echo "Created WebServerASG (min1/desired1/max2), attached to WebServerTG"

cat > frontend-tier.env <<EOF
export WEBSERVER_TG_ARN=$TG_ARN
export PUBLIC_NLB_ARN=$NLB_ARN
export PUBLIC_NLB_DNS=$NLB_DNS
EOF
echo "Wrote frontend-tier.env"
echo ""
echo "IMPORTANT: PUBLIC_NLB_DNS=$NLB_DNS"
echo "Give instances a few minutes to boot + pass health checks, then check:"
echo "  aws elbv2 describe-target-health --target-group-arn $TG_ARN"
echo "  curl http://$NLB_DNS/"
