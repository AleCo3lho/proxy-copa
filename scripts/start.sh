#!/usr/bin/env bash
# Start the WireGuard instance, wait for boot, refresh the client config with
# the new public IP (it changes on every stop/start), and print config + QR.
#
# Usage: ./scripts/start.sh
# Reads instance ID / region from terraform output; override with
# INSTANCE_ID=... AWS_REGION=... ./scripts/start.sh
set -euo pipefail

cd "$(dirname "$0")/../terraform"

INSTANCE_ID="${INSTANCE_ID:-$(terraform output -raw instance_id)}"
REGION="${AWS_REGION:-$(terraform output -raw region)}"

echo "Starting $INSTANCE_ID in $REGION ..."
aws ec2 start-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
echo "Instance running. New public IP: $PUBLIC_IP"

printf 'Waiting for SSM agent to come online '
STATUS=""
for _ in $(seq 1 60); do
  STATUS=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)
  if [ "$STATUS" = "Online" ]; then break; fi
  printf '.'
  sleep 5
done
echo

if [ "$STATUS" != "Online" ]; then
  echo "ERROR: SSM agent did not come online within 5 minutes." >&2
  exit 1
fi

# Regenerate the client config server-side with the new endpoint IP
CMD_ID=$(aws ssm send-command --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["/usr/local/bin/wg-refresh-endpoint.sh"]' \
  --query 'Command.CommandId' --output text)

CMD_STATUS="Pending"
for _ in $(seq 1 30); do
  CMD_STATUS=$(aws ssm get-command-invocation --region "$REGION" \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query 'Status' --output text 2>/dev/null || echo "Pending")
  case "$CMD_STATUS" in
    Success | Failed | Cancelled | TimedOut) break ;;
  esac
  sleep 2
done

aws ssm get-command-invocation --region "$REGION" \
  --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query 'StandardOutputContent' --output text

if [ "$CMD_STATUS" != "Success" ]; then
  echo "ERROR: SSM command finished with status $CMD_STATUS" >&2
  aws ssm get-command-invocation --region "$REGION" \
    --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query 'StandardErrorContent' --output text >&2
  exit 1
fi

echo
echo "Only the Endpoint changed (keys are stable): update it to $PUBLIC_IP in"
echo "your WireGuard app, or delete the old tunnel and re-scan the QR above."
echo "Run ./scripts/stop.sh when you're done to stop paying for compute."
