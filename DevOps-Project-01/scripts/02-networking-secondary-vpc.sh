#!/bin/bash
# 02-networking-secondary-vpc.sh
# Same pattern as 01, for SecondaryVPC (Tomcat/app tier).

set -e

aws ec2 create-vpc \
  --cidr-block 172.32.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=SecondaryVPC}]'
# -> vpc-026ec83e38deaadee
VPC_ID="vpc-026ec83e38deaadee"

aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.32.0.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=AppPublicSubnet-1a}]'
# -> subnet-0824dc2f28a3376f6

aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.32.1.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=AppPublicSubnet-1b}]'
# -> subnet-037a01d1dd34a8232

aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.32.2.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=AppPrivateSubnet-1a}]'
# -> subnet-00256f756c0374f70

aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.32.3.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=AppPrivateSubnet-1b}]'
# -> subnet-0f43027aff197a4b0

PUB_SUBNET_A="subnet-0824dc2f28a3376f6"
PUB_SUBNET_B="subnet-037a01d1dd34a8232"
PRIV_SUBNET_A="subnet-00256f756c0374f70"
PRIV_SUBNET_B="subnet-0f43027aff197a4b0"

aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=SecondaryIGW}]'
# -> igw-00508a479538cb00e
IGW_ID="igw-00508a479538cb00e"

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=AppPublicRT}]'
# -> rtb-0932fce9038d7b4c3
PUBLIC_RT="rtb-0932fce9038d7b4c3"

aws ec2 create-route --route-table-id $PUBLIC_RT \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUB_SUBNET_A
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUB_SUBNET_B

aws ec2 describe-route-tables --route-table-ids $PUBLIC_RT \
  --query 'RouteTables[0].[Routes,Associations]' --output json

aws ec2 allocate-address --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=SecondaryNATGatewayEIP}]'
# -> eipalloc-02a195a8325486793
EIP_ALLOC="eipalloc-02a195a8325486793"

aws ec2 create-nat-gateway --subnet-id $PUB_SUBNET_A --allocation-id $EIP_ALLOC \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=SecondaryNATGateway}]'
# -> nat-01f8f609702114c5d
NAT_GW="nat-01f8f609702114c5d"

aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=AppPrivateRT}]'
# -> rtb-035e231a57dfcf97c
PRIVATE_RT="rtb-035e231a57dfcf97c"

aws ec2 create-route --route-table-id $PRIVATE_RT \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIV_SUBNET_A
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIV_SUBNET_B

aws ec2 describe-route-tables --route-table-ids $PRIVATE_RT \
  --query 'RouteTables[0].[Routes,Associations]' --output json
