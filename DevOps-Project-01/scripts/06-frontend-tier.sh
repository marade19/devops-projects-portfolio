#!/bin/bash
# 06-frontend-tier.sh
# Nginx launch template + Auto Scaling Group + public Network Load Balancer.
# UserData for the launch template is in nginx-userdata.sh (base64-encode it
# and drop it into --launch-template-data as shown below).

set -e

PRIMARY_VPC="vpc-09ef7690ae00d00d1"
FRONTEND_SG="sg-011a885afddbd2a1b"
PUB_SUBNET_A="subnet-007cc8fbad0f6f00a"
PUB_SUBNET_B="subnet-07e28df467685a2f2"
PRIV_SUBNET_A="subnet-0c305ffdd67204b0e"
PRIV_SUBNET_B="subnet-06246e48e51be8747"

# Find the latest Ubuntu 24.04 AMI (don't hardcode — it changes over time)
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text --region us-east-1)

USER_DATA_B64=$(base64 -w 0 nginx-userdata.sh)

aws ec2 create-launch-template \
  --launch-template-name WebServerTemplate \
  --version-description WebServerVersion1 \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"SecurityGroupIds\": [\"$FRONTEND_SG\"],
    \"UserData\": \"$USER_DATA_B64\"
  }"
# -> lt-03dae73bfc1f5f8dc

# --- Target group + public NLB ---
aws elbv2 create-target-group \
  --name WebServerTG --protocol TCP --port 80 --vpc-id $PRIMARY_VPC \
  --target-type instance --health-check-protocol TCP --health-check-port 80
# -> arn:...targetgroup/WebServerTG/5e81c3efebccd76c
TG_ARN="arn:aws:elasticloadbalancing:us-east-1:641867104188:targetgroup/WebServerTG/5e81c3efebccd76c"

aws elbv2 create-load-balancer \
  --name PublicNLB --type network --scheme internet-facing \
  --subnets $PUB_SUBNET_A $PUB_SUBNET_B
# -> arn:...loadbalancer/net/PublicNLB/cc47569b2bfd43de
# -> DNS: PublicNLB-cc47569b2bfd43de.elb.us-east-1.amazonaws.com
NLB_ARN="arn:aws:elasticloadbalancing:us-east-1:641867104188:loadbalancer/net/PublicNLB/cc47569b2bfd43de"

aws elbv2 create-listener \
  --load-balancer-arn $NLB_ARN --protocol TCP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

# --- Auto Scaling Group, launched into PRIVATE subnets (public-facing is the NLB, not the instances) ---
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name WebServerASG \
  --launch-template LaunchTemplateName=WebServerTemplate,Version='$Latest' \
  --min-size 2 --max-size 6 --desired-capacity 2 \
  --vpc-zone-identifier "$PRIV_SUBNET_A,$PRIV_SUBNET_B" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB --health-check-grace-period 300

# --- To ship an updated UserData later (e.g. the reverse-proxy config), create
#     a new launch template version, set it default, then trigger a refresh: ---
#
# aws ec2 create-launch-template-version --launch-template-name WebServerTemplate \
#   --source-version '$Latest' --version-description WebServerVersionN \
#   --launch-template-data "{\"UserData\": \"$(base64 -w 0 nginx-userdata.sh)\"}"
# aws ec2 modify-launch-template --launch-template-name WebServerTemplate --default-version '$Latest'
# aws autoscaling start-instance-refresh --auto-scaling-group-name WebServerASG
