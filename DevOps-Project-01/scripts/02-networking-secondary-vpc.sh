#!/bin/bash
# 02-networking-secondary-vpc.sh (rebuild — dynamic ID capture)
set -e

VPC_ID=$(aws ec2 create-vpc --cidr-block 172.32.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=SecondaryVPC}]' \
  --query 'Vpc.VpcId' --output text)
echo "VPC_ID=$VPC_ID"

PUB_SUBNET_A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.32.0.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=AppPublicSubnet-1a}]' \
  --query 'Subnet.SubnetId' --output text)

PUB_SUBNET_B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.32.1.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=AppPublicSubnet-1b}]' \
  --query 'Subnet.SubnetId' --output text)

PRIV_SUBNET_A=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.32.2.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=AppPrivateSubnet-1a}]' \
  --query 'Subnet.SubnetId' --output text)

PRIV_SUBNET_B=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 172.32.3.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=AppPrivateSubnet-1b}]' \
  --query 'Subnet.SubnetId' --output text)

echo "PUB_SUBNET_A=$PUB_SUBNET_A PUB_SUBNET_B=$PUB_SUBNET_B"
echo "PRIV_SUBNET_A=$PRIV_SUBNET_A PRIV_SUBNET_B=$PRIV_SUBNET_B"

IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=SecondaryIGW}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
echo "IGW_ID=$IGW_ID"

PUBLIC_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=AppPublicRT}]' \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route --route-table-id $PUBLIC_RT \
  --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID > /dev/null
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUB_SUBNET_A > /dev/null
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUB_SUBNET_B > /dev/null

echo "--- verifying public route table ---"
aws ec2 describe-route-tables --route-table-ids $PUBLIC_RT \
  --query 'RouteTables[0].[Routes,Associations]' --output json

EIP_ALLOC=$(aws ec2 allocate-address --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=SecondaryNATGatewayEIP}]' \
  --query 'AllocationId' --output text)

NAT_GW=$(aws ec2 create-nat-gateway --subnet-id $PUB_SUBNET_A --allocation-id $EIP_ALLOC \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=SecondaryNATGateway}]' \
  --query 'NatGateway.NatGatewayId' --output text)
echo "NAT_GW=$NAT_GW  (waiting for 'available'...)"
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW

PRIVATE_RT=$(aws ec2 create-route-table --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=AppPrivateRT}]' \
  --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route --route-table-id $PRIVATE_RT \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW > /dev/null
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIV_SUBNET_A > /dev/null
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIV_SUBNET_B > /dev/null

echo "--- verifying private route table ---"
aws ec2 describe-route-tables --route-table-ids $PRIVATE_RT \
  --query 'RouteTables[0].[Routes,Associations]' --output json

cat > secondary-vpc.env <<EOF
export SECONDARY_VPC_ID=$VPC_ID
export SECONDARY_PUB_SUBNET_A=$PUB_SUBNET_A
export SECONDARY_PUB_SUBNET_B=$PUB_SUBNET_B
export SECONDARY_PRIV_SUBNET_A=$PRIV_SUBNET_A
export SECONDARY_PRIV_SUBNET_B=$PRIV_SUBNET_B
export SECONDARY_PRIVATE_RT=$PRIVATE_RT
EOF
echo "Wrote secondary-vpc.env"
