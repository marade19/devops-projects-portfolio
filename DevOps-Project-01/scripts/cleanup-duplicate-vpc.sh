#!/bin/bash
# cleanup-duplicate-vpc.sh
# Removes the accidental duplicate VPC (vpc-0102c6eb7ae1cd333), created when
# 01-networking-primary-vpc.sh ended up with SecondaryVPC's content.
set -e

VPC_ID="vpc-0102c6eb7ae1cd333"
NAT_GW="nat-028c68a89caa08fd2"
IGW_ID="igw-0ba2112dab0ef6076"
PUBLIC_RT="rtb-09583af9c833d79df"
PRIVATE_RT="rtb-0c51cf4383f9b3002"
SUBNETS="subnet-07ef51b31b90541cc subnet-0c13543e6db058130 subnet-074dd758d0ba78c4b subnet-0025590c46f3b320a"

# Find the Elastic IP allocation attached to this NAT gateway
EIP_ALLOC=$(aws ec2 describe-nat-gateways --nat-gateway-ids $NAT_GW \
  --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' --output text)
echo "EIP_ALLOC=$EIP_ALLOC"

echo "Deleting NAT Gateway (this takes a minute or two)..."
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW
aws ec2 wait nat-gateway-deleted --nat-gateway-ids $NAT_GW
echo "NAT Gateway deleted."

aws ec2 release-address --allocation-id $EIP_ALLOC
echo "EIP released."

aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
echo "IGW detached and deleted."

aws ec2 delete-route-table --route-table-id $PUBLIC_RT
aws ec2 delete-route-table --route-table-id $PRIVATE_RT
echo "Route tables deleted."

for SUBNET in $SUBNETS; do
  aws ec2 delete-subnet --subnet-id $SUBNET
  echo "Deleted subnet $SUBNET"
done

aws ec2 delete-vpc --vpc-id $VPC_ID
echo "VPC $VPC_ID deleted. Cleanup complete."
