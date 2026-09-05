#!/bin/bash
# cleanup-duplicate-vpc-part2.sh
# Finishes the cleanup: disassociate route tables from their subnets first,
# then delete route tables, subnets, and finally the VPC.
set -e

VPC_ID="vpc-0102c6eb7ae1cd333"
PUBLIC_RT="rtb-09583af9c833d79df"
PRIVATE_RT="rtb-0c51cf4383f9b3002"
PUBLIC_ASSOCS="rtbassoc-079bc8e4ac638c8b0 rtbassoc-076776088065aa849"
PRIVATE_ASSOCS="rtbassoc-0aa29cc1e936781b6 rtbassoc-029c497c2e0c10aae"
SUBNETS="subnet-07ef51b31b90541cc subnet-0c13543e6db058130 subnet-074dd758d0ba78c4b subnet-0025590c46f3b320a"

for ASSOC in $PUBLIC_ASSOCS $PRIVATE_ASSOCS; do
  aws ec2 disassociate-route-table --association-id $ASSOC
  echo "Disassociated $ASSOC"
done

aws ec2 delete-route-table --route-table-id $PUBLIC_RT
aws ec2 delete-route-table --route-table-id $PRIVATE_RT
echo "Route tables deleted."

for SUBNET in $SUBNETS; do
  aws ec2 delete-subnet --subnet-id $SUBNET
  echo "Deleted subnet $SUBNET"
done

aws ec2 delete-vpc --vpc-id $VPC_ID
echo "VPC $VPC_ID deleted. Cleanup complete."
