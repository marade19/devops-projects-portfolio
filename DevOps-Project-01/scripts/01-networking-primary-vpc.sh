#!/bin/bash
# 01-networking-primary-vpc.sh
# Creates PrimaryVPC (frontend/Nginx tier + RDS) with public + private subnets,
# an Internet Gateway, a NAT Gateway, and correctly-associated route tables.
#
# IMPORTANT: this reflects the SECOND (working) build. The first attempt failed
# because the NAT Gateway sat in a subnet with no IGW route, and the route
# tables existed but were never associated with any subnet. See BUILD-LOG.md
# problem #1. This version verifies every association before moving on.

set -e

REGION="us-east-1"

# --- VPC ---
aws ec2 create-vpc \
  --cidr-block 192.168.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=PrimaryVPC}]'
# -> VpcId: vpc-09ef7690ae00d00d1

VPC_ID="vpc-09ef7690ae00d00d1"

# --- Subnets: 2 public, 2 private, across 2 AZs ---
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 192.168.0.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=PublicSubnet-1a}]'
# -> subnet-007cc8fbad0f6f00a

aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 192.168.1.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=PublicSubnet-1b}]'
# -> subnet-07e28df467685a2f2

aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 192.168.2.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=PrivateSubnet-1a}]'
# -> subnet-0c305ffdd67204b0e

aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 192.168.3.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=PrivateSubnet-1b}]'
# -> subnet-06246e48e51be8747

PUB_SUBNET_A="subnet-007cc8fbad0f6f00a"
PUB_SUBNET_B="subnet-07e28df467685a2f2"
PRIV_SUBNET_A="subnet-0c305ffdd67204b0e"
PRIV_SUBNET_B="subnet-06246e48e51be8747"

# --- Internet Gateway ---
aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=PrimaryIGW}]'
# -> igw-01a08ee3a880d6b1a
IGW_ID="igw-01a08ee3a880d6b1a"

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

# --- Public route table ---
aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=PublicRT}]'
# -> rtb-0d79f1b50369f6499
PUBLIC_RT="rtb-0d79f1b50369f6499"

aws ec2 create-route --route-table-id $PUBLIC_RT \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUB_SUBNET_A
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUB_SUBNET_B

# VERIFY before continuing — this step is what was skipped the first time around
aws ec2 describe-route-tables --route-table-ids $PUBLIC_RT \
  --query 'RouteTables[0].[Routes,Associations]' --output json

# --- NAT Gateway (in a PUBLIC subnet — this was the root cause of the first failure) ---
aws ec2 allocate-address --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=PrimaryNATGatewayEIP}]'
# -> eipalloc-08d060c4c2ae411b8
EIP_ALLOC="eipalloc-08d060c4c2ae411b8"

aws ec2 create-nat-gateway --subnet-id $PUB_SUBNET_A --allocation-id $EIP_ALLOC \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=PrimaryNATGateway}]'
# -> nat-04c6150d7e6f71c4a
NAT_GW="nat-04c6150d7e6f71c4a"

# wait for it: aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GW --query 'NatGateways[0].State' --output text

# --- Private route table ---
aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=PrivateRT}]'
# -> rtb-04881837908606ffb
PRIVATE_RT="rtb-04881837908606ffb"

aws ec2 create-route --route-table-id $PRIVATE_RT \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW

aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIV_SUBNET_A
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIV_SUBNET_B

# VERIFY again
aws ec2 describe-route-tables --route-table-ids $PRIVATE_RT \
  --query 'RouteTables[0].[Routes,Associations]' --output json
