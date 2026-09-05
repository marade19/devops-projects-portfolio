#!/bin/bash
# 05-rds.sh (rebuild — secure password prompt, real waiter)
# Sized for AWS Free Tier (db.t3.micro, single-AZ).
set -e

source ./security-groups.env
source ./primary-vpc.env

read -s -p "Enter a master password for the new RDS instance (won't echo): " DB_PASSWORD
echo
read -s -p "Confirm password: " DB_PASSWORD_CONFIRM
echo

if [ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]; then
  echo "Passwords didn't match. Aborting."
  exit 1
fi

aws rds create-db-subnet-group \
  --db-subnet-group-name javaapp-db-subnet-group \
  --db-subnet-group-description "Private subnets for RDS" \
  --subnet-ids $PRIMARY_PRIV_SUBNET_A $PRIMARY_PRIV_SUBNET_B > /dev/null
echo "Created db-subnet-group."

aws rds create-db-instance \
  --db-instance-identifier prod-mysql \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password "$DB_PASSWORD" \
  --allocated-storage 20 \
  --vpc-security-group-ids $DATABASE_SG \
  --db-subnet-group-name javaapp-db-subnet-group \
  --no-publicly-accessible > /dev/null
echo "RDS instance creating — this takes 5-10 minutes. Polling..."

aws rds wait db-instance-available --db-instance-identifier prod-mysql
echo "RDS is available."

RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier prod-mysql \
  --query 'DBInstances[0].Endpoint.Address' --output text)
RDS_PORT=$(aws rds describe-db-instances --db-instance-identifier prod-mysql \
  --query 'DBInstances[0].Endpoint.Port' --output text)

echo "RDS_ENDPOINT=$RDS_ENDPOINT"
echo "RDS_PORT=$RDS_PORT"

# Password is deliberately NOT written to this file — pass it via prompt
# again wherever it's next needed (e.g. exporting DB_PASSWORD before building
# the WAR, or into tomcat-userdata.sh).
cat > rds.env <<EOF
export RDS_ENDPOINT=$RDS_ENDPOINT
export RDS_PORT=$RDS_PORT
EOF
echo "Wrote rds.env (endpoint only — password was NOT saved to disk)"

echo ""
echo "NEXT: connect via SSM session into an instance inside the VPC and run:"
echo "  mysql -h $RDS_ENDPOINT -u admin -p"
echo "  CREATE DATABASE javaapp;"
echo "  USE javaapp;"
echo "  CREATE TABLE users ("
echo "      id INT AUTO_INCREMENT PRIMARY KEY,"
echo "      username VARCHAR(50) NOT NULL UNIQUE,"
echo "      password VARCHAR(255) NOT NULL,"
echo "      email VARCHAR(100) NOT NULL UNIQUE,"
echo "      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP"
echo "  );"
echo "  CREATE INDEX idx_username ON users(username);"
echo "  CREATE INDEX idx_email ON users(email);"
