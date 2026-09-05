#!/bin/bash
# 04-security-groups.sh (rebuild — dynamic ID capture)
#
# NOTE on cross-VPC rules: --source-group only works within a single VPC.
# FrontendSG (PrimaryVPC) and TomcatSG (SecondaryVPC) can't reference each
# other by group ID even though the Transit Gateway connects them — AWS
# returns "InvalidGroup.NotFound ... belong to different networks." So any
# rule that needs to allow traffic FROM the other VPC uses a CIDR block
# instead of a security-group reference.
set -e

source ./primary-vpc.env
source ./secondary-vpc.env

# --- FrontendSG (PrimaryVPC) — public HTTP/HTTPS ---
FRONTEND_SG=$(aws ec2 create-security-group --group-name FrontendSG \
  --description "Security group for frontend Nginx servers" --vpc-id $PRIMARY_VPC_ID \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG \
  --protocol tcp --port 443 --cidr 0.0.0.0/0 > /dev/null
echo "FRONTEND_SG=$FRONTEND_SG"

# --- DatabaseSG (PrimaryVPC) — MySQL, only from app tiers ---
DATABASE_SG=$(aws ec2 create-security-group --group-name DatabaseSG \
  --description "Security group for RDS MySQL" --vpc-id $PRIMARY_VPC_ID \
  --query 'GroupId' --output text)

# From FrontendSG directly (same VPC, group reference works)
aws ec2 authorize-security-group-ingress --group-id $DATABASE_SG \
  --protocol tcp --port 3306 --source-group $FRONTEND_SG > /dev/null

# From SecondaryVPC's private subnets (Tomcat is what actually talks to MySQL;
# cross-VPC, so CIDR not group reference)
aws ec2 authorize-security-group-ingress --group-id $DATABASE_SG \
  --protocol tcp --port 3306 --cidr 172.32.2.0/24 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $DATABASE_SG \
  --protocol tcp --port 3306 --cidr 172.32.3.0/24 > /dev/null
echo "DATABASE_SG=$DATABASE_SG"

# --- TomcatSG (SecondaryVPC) — app port, from Nginx AND from its own subnets ---
TOMCAT_SG=$(aws ec2 create-security-group --group-name TomcatSG \
  --description "Security group for Tomcat app tier" --vpc-id $SECONDARY_VPC_ID \
  --query 'GroupId' --output text)

# From PrimaryVPC's private subnets (where Nginx lives) — cross-VPC, CIDR
aws ec2 authorize-security-group-ingress --group-id $TOMCAT_SG \
  --protocol tcp --port 8080 --cidr 192.168.2.0/24 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $TOMCAT_SG \
  --protocol tcp --port 8080 --cidr 192.168.3.0/24 > /dev/null

# From SecondaryVPC's OWN private subnets — required because the Internal NLB's
# health-check probes originate from ENIs in the target's own subnets, not from
# wherever the caller lives. Without this, target health checks fail even
# though the app itself is reachable.
aws ec2 authorize-security-group-ingress --group-id $TOMCAT_SG \
  --protocol tcp --port 8080 --cidr 172.32.2.0/24 > /dev/null
aws ec2 authorize-security-group-ingress --group-id $TOMCAT_SG \
  --protocol tcp --port 8080 --cidr 172.32.3.0/24 > /dev/null
echo "TOMCAT_SG=$TOMCAT_SG"

cat > security-groups.env <<EOF
export FRONTEND_SG=$FRONTEND_SG
export DATABASE_SG=$DATABASE_SG
export TOMCAT_SG=$TOMCAT_SG
EOF
echo "Wrote security-groups.env"
