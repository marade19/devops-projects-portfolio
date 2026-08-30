#!/bin/bash
# 03-transit-gateway.sh
# Connects PrimaryVPC and SecondaryVPC so the frontend and app tiers can
# reach each other privately, without going over the public internet.

set -e

PRIMARY_VPC="vpc-09ef7690ae00d00d1"
SECONDARY_VPC="vpc-026ec83e38deaadee"
PRIMARY_PRIVATE_SUBNET_A="subnet-0c305ffdd67204b0e"
PRIMARY_PRIVATE_SUBNET_B="subnet-06246e48e51be8747"
SECONDARY_PRIVATE_SUBNET_A="subnet-00256f756c0374f70"
SECONDARY_PRIVATE_SUBNET_B="subnet-0f43027aff197a4b0"
PRIMARY_PRIVATE_RT="rtb-04881837908606ffb"
SECONDARY_PRIVATE_RT="rtb-035e231a57dfcf97c"

aws ec2 create-transit-gateway \
  --description "Connects PrimaryVPC and SecondaryVPC" \
  --tag-specifications 'ResourceType=transit-gateway,Tags=[{Key=Name,Value=MainTGW}]'
# -> tgw-067f758cd9ef73ace
TGW_ID="tgw-067f758cd9ef73ace"

# wait for available: aws ec2 describe-transit-gateways --transit-gateway-ids $TGW_ID --query 'TransitGateways[0].State' --output text

aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_ID \
  --vpc-id $PRIMARY_VPC \
  --subnet-ids $PRIMARY_PRIVATE_SUBNET_A $PRIMARY_PRIVATE_SUBNET_B \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=PrimaryVPC-Attachment}]'
# -> tgw-attach-0a9361b8d31aac128

aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_ID \
  --vpc-id $SECONDARY_VPC \
  --subnet-ids $SECONDARY_PRIVATE_SUBNET_A $SECONDARY_PRIVATE_SUBNET_B \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=SecondaryVPC-Attachment}]'
# -> tgw-attach-045341e837943a856

# wait for both attachments to show "available":
# aws ec2 describe-transit-gateway-vpc-attachments --transit-gateway-attachment-ids <id1> <id2> \
#   --query 'TransitGatewayVpcAttachments[*].[TransitGatewayAttachmentId,State]' --output table

# Cross-VPC routes — each VPC's private route table needs a route to the OTHER
# VPC's CIDR block via the Transit Gateway, or traffic has no way back.
aws ec2 create-route --route-table-id $PRIMARY_PRIVATE_RT \
  --destination-cidr-block 172.32.0.0/16 --transit-gateway-id $TGW_ID

aws ec2 create-route --route-table-id $SECONDARY_PRIVATE_RT \
  --destination-cidr-block 192.168.0.0/16 --transit-gateway-id $TGW_ID
