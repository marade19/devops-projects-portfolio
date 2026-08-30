#!/bin/bash
# 04-security-groups.sh
#
# NOTE on cross-VPC rules: --source-group only works within a single VPC.
# FrontendSG (PrimaryVPC) and TomcatSG (SecondaryVPC) can't reference each
# other by group ID even though the Transit Gateway connects them — AWS
# returns "InvalidGroup.NotFound ... belong to different networks." So any
# rule that needs to allow traffic FROM the other VPC uses a CIDR block
# instead of a security-group reference. See BUILD-LOG.md problems #7 and #8.

set -e

PRIMARY_VPC="vpc-09ef7690ae00d00d1"
SECONDARY_VPC="vpc-026ec83e38deaadee"

# --- FrontendSG (PrimaryVPC) — public HTTP/HTTPS ---
aws ec2 create-security-group --group-name FrontendSG \
  --description "Security group for frontend Nginx servers" --vpc-id $PRIMARY_VPC
# -> sg-011a885afddbd2a1b
FRONTEND_SG="sg-011a885afddbd2a1b"

aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $FRONTEND_SG \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

# --- DatabaseSG (PrimaryVPC) — MySQL, only from app tiers ---
aws ec2 create-security-group --group-name DatabaseSG \
  --description "Security group for RDS MySQL" --vpc-id $PRIMARY_VPC
# -> sg-067a0f3830485ca20
DATABASE_SG="sg-067a0f3830485ca20"

# From FrontendSG directly (same VPC, group reference works)
aws ec2 authorize-security-group-ingress --group-id $DATABASE_SG \
  --protocol tcp --port 3306 --source-group $FRONTEND_SG

# From SecondaryVPC's private subnets (Tomcat is what actually talks to MySQL;
# cross-VPC, so CIDR not group reference)
aws ec2 authorize-security-group-ingress --group-id $DATABASE_SG \
  --protocol tcp --port 3306 --cidr 172.32.2.0/24
aws ec2 authorize-security-group-ingress --group-id $DATABASE_SG \
  --protocol tcp --port 3306 --cidr 172.32.3.0/24

# --- TomcatSG (SecondaryVPC) — app port, from Nginx AND from its own subnets ---
aws ec2 create-security-group --group-name TomcatSG \
  --description "Security group for Tomcat app tier" --vpc-id $SECONDARY_VPC
# -> sg-0fe75519e368bdd76
TOMCAT_SG="sg-0fe75519e368bdd76"

# From PrimaryVPC's private subnets (where Nginx lives) — cross-VPC, CIDR
aws ec2 authorize-security-group-ingress --group-id $TOMCAT_SG \
  --protocol tcp --port 8080 --cidr 192.168.2.0/24
aws ec2 authorize-security-group-ingress --group-id $TOMCAT_SG \
  --protocol tcp --port 8080 --cidr 192.168.3.0/24

# From SecondaryVPC's OWN private subnets — required because the Internal NLB's
# health-check probes originate from ENIs in the target's own subnets, not from
# wherever the caller lives. Without this, target health checks fail even
# though the app itself is reachable. See BUILD-LOG.md problem #8.
aws ec2 authorize-security-group-ingress --group-id $TOMCAT_SG \
  --protocol tcp --port 8080 --cidr 172.32.2.0/24
aws ec2 authorize-security-group-ingress --group-id $TOMCAT_SG \
  --protocol tcp --port 8080 --cidr 172.32.3.0/24
