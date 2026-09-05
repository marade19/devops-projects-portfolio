#!/bin/bash
# 09-verify-db.sh
# Avoids the nested-quoting problem entirely: builds the remote script as a
# file, base64-encodes it, and has SSM decode+run it. The password never has
# to survive being embedded in a quoted --parameters string.
set -e

source ./rds.env

read -s -p "Re-enter the RDS master password (exactly as used when creating it): " DB_PASSWORD
echo

INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names TomcatASG \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
echo "Targeting instance: $INSTANCE_ID"

cat > /tmp/remote-check.sh <<REMOTE
#!/bin/bash
mysql -h $RDS_ENDPOINT -u admin -p"$DB_PASSWORD" -e "USE javaapp; SHOW TABLES;"
REMOTE

REMOTE_B64=$(base64 -w 0 /tmp/remote-check.sh)
rm /tmp/remote-check.sh

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters "{\"commands\":[\"echo $REMOTE_B64 | base64 -d > /tmp/check.sh && bash /tmp/check.sh; rm -f /tmp/check.sh\"]}" \
  --query 'Command.CommandId' --output text)

echo "Sent: $COMMAND_ID (waiting...)"
sleep 5
aws ssm wait command-executed --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" || true

echo "--- result ---"
aws ssm get-command-invocation \
  --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
  --query '[Status,StandardOutputContent,StandardErrorContent]' --output text
