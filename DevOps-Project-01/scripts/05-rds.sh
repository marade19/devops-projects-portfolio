#!/bin/bash
# 05-rds.sh
# RDS MySQL, sized for AWS Free Tier (db.t3.micro, single-AZ) rather than the
# README's db.t3.medium/Multi-AZ, to avoid unnecessary cost for a learning project.

set -e

DATABASE_SG="sg-067a0f3830485ca20"
PRIVATE_SUBNET_A="subnet-0c305ffdd67204b0e"
PRIVATE_SUBNET_B="subnet-06246e48e51be8747"

aws rds create-db-subnet-group \
  --db-subnet-group-name javaapp-db-subnet-group \
  --db-subnet-group-description "Private subnets for RDS" \
  --subnet-ids $PRIVATE_SUBNET_A $PRIVATE_SUBNET_B

aws rds create-db-instance \
  --db-instance-identifier prod-mysql \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --master-username admin \
  --master-user-password "REPLACE_WITH_YOUR_OWN_PASSWORD" \
  --allocated-storage 20 \
  --vpc-security-group-ids $DATABASE_SG \
  --db-subnet-group-name javaapp-db-subnet-group \
  --no-publicly-accessible

# wait for available:
# aws rds describe-db-instances --db-instance-identifier prod-mysql \
#   --query 'DBInstances[0].DBInstanceStatus' --output text

# Once available, get the endpoint:
# aws rds describe-db-instances --db-instance-identifier prod-mysql \
#   --query 'DBInstances[0].[Endpoint.Address,Endpoint.Port]' --output table

# RDS is --no-publicly-accessible, so you can't run this from your laptop.
# Connect from inside the VPC (e.g. via SSM session into an EC2 instance) and run:
#
#   mysql -h <rds-endpoint> -u admin -p
#
#   CREATE DATABASE javaapp;
#   USE javaapp;
#   CREATE TABLE users (
#       id INT AUTO_INCREMENT PRIMARY KEY,
#       username VARCHAR(50) NOT NULL UNIQUE,
#       password VARCHAR(255) NOT NULL,
#       email VARCHAR(100) NOT NULL UNIQUE,
#       created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
#   );
#   CREATE INDEX idx_username ON users(username);
#   CREATE INDEX idx_email ON users(email);
