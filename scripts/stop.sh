#!/usr/bin/env bash
# Stop the WireGuard instance so you only pay for the EBS volume (~$0.64/mo).
#
# Usage: ./scripts/stop.sh
# Reads instance ID / region from terraform output; override with
# INSTANCE_ID=... AWS_REGION=... ./scripts/stop.sh
set -euo pipefail

cd "$(dirname "$0")/../terraform"

INSTANCE_ID="${INSTANCE_ID:-$(terraform output -raw instance_id)}"
REGION="${AWS_REGION:-$(terraform output -raw region)}"

echo "Stopping $INSTANCE_ID in $REGION ..."
aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID" --region "$REGION"

echo "Instance stopped. You are now only paying for the 8 GB EBS volume."
echo "The public IP will be different next time — ./scripts/start.sh handles that."
