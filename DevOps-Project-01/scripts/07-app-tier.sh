#!/bin/bash
# 07-app-tier.sh
# S3 bucket for the WAR artifact, IAM role (S3 read + SSM — baked into the
# launch template from the start this time, see BUILD-LOG.md "IAM roles"
# section), Tomcat launch template, ASG, and an INTERNAL NLB in front of it
# (per the original README's architecture — Nginx's upstream points at this
# internal NLB's DNS name, not at instance IPs directly).

set -e

SECONDARY_VPC="vpc-026ec83e38deaadee"
TOMCAT_SG="sg-0fe75519e368bdd76"
PRIV_SUBNET_A="subnet-00256f756c0374f70"
PRIV_SUBNET_B="subnet-0f43027aff197a4b0"

# --- S3 bucket for the WAR file ---
aws s3 mb s3://devopsproject01-artifacts-1787865399
aws s3 cp target/dptweb-1.0.war s3://devopsproject01-artifacts-1787865399/dptweb-1.0.war

# --- IAM role: S3 read (scoped to this bucket only) + SSM ---
aws iam create-role --role-name TomcatS3Role --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Principal": {"Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole"}]
}'

aws iam put-role-policy --role-name TomcatS3Role --policy-name S3ReadArtifacts --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::devopsproject01-artifacts-1787865399/*"}]
}'

aws iam attach-role-policy --role-name TomcatS3Role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile --instance-profile-name TomcatS3Profile
aws iam add-role-to-instance-profile --instance-profile-name TomcatS3Profile --role-name TomcatS3Role
# wait ~15s for propagation before creating the launch template below

# --- Launch template (UserData is tomcat-userdata.sh, final/working version) ---
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text --region us-east-1)

USER_DATA_B64=$(base64 -w 0 tomcat-userdata.sh)

aws ec2 create-launch-template \
  --launch-template-name TomcatServerTemplate \
  --version-description TomcatVersion1 \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"SecurityGroupIds\": [\"$TOMCAT_SG\"],
    \"IamInstanceProfile\": {\"Name\": \"TomcatS3Profile\"},
    \"UserData\": \"$USER_DATA_B64\"
  }"
# -> lt-099e9b4812a72eebb

# --- Internal target group + internal NLB (no target-group-arns on ASG create;
#     attach separately so it stays in sync automatically as instances are replaced) ---
aws elbv2 create-target-group \
  --name TomcatTG --protocol TCP --port 8080 --vpc-id $SECONDARY_VPC \
  --target-type instance --health-check-protocol TCP --health-check-port 8080
# -> arn:...targetgroup/TomcatTG/7b15316e7252dc94
TG_ARN="arn:aws:elasticloadbalancing:us-east-1:641867104188:targetgroup/TomcatTG/7b15316e7252dc94"

aws elbv2 create-load-balancer \
  --name InternalTomcatNLB --type network --scheme internal \
  --subnets $PRIV_SUBNET_A $PRIV_SUBNET_B
# -> arn:...loadbalancer/net/InternalTomcatNLB/49c5132eae8ab1e2
# -> DNS: InternalTomcatNLB-49c5132eae8ab1e2.elb.us-east-1.amazonaws.com
NLB_ARN="arn:aws:elasticloadbalancing:us-east-1:641867104188:loadbalancer/net/InternalTomcatNLB/49c5132eae8ab1e2"

aws elbv2 create-listener \
  --load-balancer-arn $NLB_ARN --protocol TCP --port 8080 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

# --- ASG, then attach the target group (auto-registers current + future instances) ---
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name TomcatASG \
  --launch-template LaunchTemplateName=TomcatServerTemplate,Version='$Latest' \
  --min-size 2 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "$PRIV_SUBNET_A,$PRIV_SUBNET_B" \
  --health-check-type EC2 --health-check-grace-period 300

aws autoscaling attach-load-balancer-target-groups \
  --auto-scaling-group-name TomcatASG \
  --target-group-arns $TG_ARN

# --- To ship an updated WAR or UserData later: ---
#
# aws s3 cp target/dptweb-1.0.war s3://devopsproject01-artifacts-1787865399/dptweb-1.0.war
# aws ec2 create-launch-template-version --launch-template-name TomcatServerTemplate \
#   --source-version '$Latest' --version-description TomcatVersionN \
#   --launch-template-data "{\"UserData\": \"$(base64 -w 0 tomcat-userdata.sh)\"}"
# aws ec2 modify-launch-template --launch-template-name TomcatServerTemplate --default-version '$Latest'
# aws autoscaling start-instance-refresh --auto-scaling-group-name TomcatASG
