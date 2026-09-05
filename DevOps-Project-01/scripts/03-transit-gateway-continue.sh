#!/bin/bash
# 03-transit-gateway-continue.sh
# Picks up after TGW creation (tgw-0cb6876724edd1dcf already exists) since
# `aws ec2 wait transit-gateway-available` / `transit-gateway-attachment-available`
# aren't real waiters — only nat-gateway-available is. Polling manually instead.
set -e

source ./primary-vpc.env
source ./secondary-vpc.env

TGW_ID="tgw-0cb6876724edd1dcf"

echo "Polling for TGW to become available..."
while true; do
  STATE=$(aws ec2 describe-transit-gateways --transit-gateway-ids $TGW_ID \
    --query 'TransitGateways[0].State' --output text)
  echo "  state: $STATE"
  [ "$STATE" == "available" ] && break
  sleep 10
done

PRIMARY_ATTACH=$(aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_ID \
  --vpc-id $PRIMARY_VPC_ID \
  --subnet-ids $PRIMARY_PRIV_SUBNET_A $PRIMARY_PRIV_SUBNET_B \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=PrimaryVPC-Attachment}]' \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)

SECONDARY_ATTACH=$(aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_ID \
  --vpc-id $SECONDARY_VPC_ID \
  --subnet-ids $SECONDARY_PRIV_SUBNET_A $SECONDARY_PRIV_SUBNET_B \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=SecondaryVPC-Attachment}]' \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' --output text)

echo "PRIMARY_ATTACH=$PRIMARY_ATTACH  SECONDARY_ATTACH=$SECONDARY_ATTACH"
echo "Polling for both attachments to become available..."
while true; do
  STATE1=$(aws ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids $PRIMARY_ATTACH \
    --query 'TransitGatewayVpcAttachments[0].State' --output text)
  STATE2=$(aws ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids $SECONDARY_ATTACH \
    --query 'TransitGatewayVpcAttachments[0].State' --output text)
  echo "  primary: $STATE1   secondary: $STATE2"
  [ "$STATE1" == "available" ] && [ "$STATE2" == "available" ] && break
  sleep 10
done

# Cross-VPC routes — each VPC's private route table needs a route to the OTHER
# VPC's CIDR block via the Transit Gateway, or traffic has no way back.
aws ec2 create-route --route-table-id $PRIMARY_PRIVATE_RT \
  --destination-cidr-block 172.32.0.0/16 --transit-gateway-id $TGW_ID

aws ec2 create-route --route-table-id $SECONDARY_PRIVATE_RT \
  --destination-cidr-block 192.168.0.0/16 --transit-gateway-id $TGW_ID

echo "--- verifying cross-VPC routes ---"
aws ec2 describe-route-tables --route-table-ids $PRIMARY_PRIVATE_RT $SECONDARY_PRIVATE_RT \
  --query 'RouteTables[*].[RouteTableId,Routes]' --output json

cat > transit-gateway.env <<EOF
export TGW_ID=$TGW_ID
export PRIMARY_ATTACH=$PRIMARY_ATTACH
export SECONDARY_ATTACH=$SECONDARY_ATTACH
EOF
echo "Wrote transit-gateway.env"
