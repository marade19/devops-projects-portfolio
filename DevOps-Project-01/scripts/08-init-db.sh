#!/bin/bash
# 08-init-db.sh
# Runs the CREATE DATABASE / CREATE TABLE SQL against the new RDS instance
# via SSM RunCommand on a TomcatASG instance (it already has the SSM agent +
# IAM role from TomcatS3Profile; the frontend/Nginx instances do not).
set -e

source ./rds.env

read -s -p "Re-enter the RDS master password: " DB_PASSWORD
echo

INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names TomcatASG \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
echo "Targeting instance: $INSTANCE_ID"

SQL='CREATE DATABASE IF NOT EXISTS javaapp;
USE javaapp;
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_username ON users(username);
CREATE INDEX idx_email ON users(email);'

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    \"apt-get update -y\",
    \"apt-get install -y mysql-client\",
    \"mysql -h $RDS_ENDPOINT -u admin -p'$DB_PASSWORD' -e \\\"$SQL\\\" 2>&1 || echo INDEX_MAY_ALREADY_EXIST\"
  ]" \
  --query 'Command.CommandId' --output text)

echo "Sent SSM command: $COMMAND_ID  (waiting for it to finish...)"
aws ssm wait command-executed --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" || true

echo "--- command output ---"
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
  --query '[Status,StandardOutputContent,StandardErrorContent]' --output text
