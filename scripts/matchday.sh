#!/usr/bin/env bash
# Full match-day cycle when you destroy everything between games:
#
#   ./scripts/matchday.sh up     terraform apply, wait for WireGuard setup, install
#                        the fresh client config locally, connect the tunnel
#   ./scripts/matchday.sh down   disconnect the tunnel, terraform destroy
#
# Each cycle creates a brand-new instance (new keys + new IP), so the whole
# client config is fetched via SSM and reinstalled — nothing to edit by hand.
# Requires: terraform, aws cli (with credentials), wireguard-tools (brew).
set -euo pipefail

cd "$(dirname "$0")/../terraform"

TUNNEL=proxy-copa
WG_CONF="/opt/homebrew/etc/wireguard/$TUNNEL.conf"

usage() {
  echo "Usage: $0 up|down" >&2
  exit 1
}

[ $# -eq 1 ] || usage

case "$1" in

  up)
    echo "==> terraform apply (remove -auto-approve here if you want to review the plan)"
    terraform apply -auto-approve

    INSTANCE_ID=$(terraform output -raw instance_id)
    REGION=$(terraform output -raw region)
    PUBLIC_IP=$(terraform output -raw public_ip)

    printf '==> Waiting for SSM agent to come online '
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

    # cloud-init needs a few minutes to install WireGuard and generate keys;
    # the remote command waits for client.conf to appear, then prints it.
    echo "==> Waiting for WireGuard first-boot setup and fetching client config"
    CMD_ID=$(aws ssm send-command --region "$REGION" \
      --instance-ids "$INSTANCE_ID" \
      --document-name "AWS-RunShellScript" \
      --parameters '{"commands":["for _ in $(seq 1 120); do [ -f /etc/wireguard/client.conf ] && break; sleep 5; done","cat /etc/wireguard/client.conf"]}' \
      --query 'Command.CommandId' --output text)

    CMD_STATUS="Pending"
    for _ in $(seq 1 150); do
      CMD_STATUS=$(aws ssm get-command-invocation --region "$REGION" \
        --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
        --query 'Status' --output text 2>/dev/null || echo "Pending")
      case "$CMD_STATUS" in
        Success | Failed | Cancelled | TimedOut) break ;;
      esac
      sleep 5
    done
    if [ "$CMD_STATUS" != "Success" ]; then
      echo "ERROR: fetching client config failed (status: $CMD_STATUS)" >&2
      exit 1
    fi

    CONFIG=$(aws ssm get-command-invocation --region "$REGION" \
      --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
      --query 'StandardOutputContent' --output text)

    if ! printf '%s' "$CONFIG" | grep -q 'PrivateKey' ||
      ! printf '%s' "$CONFIG" | grep -q 'Endpoint'; then
      echo "ERROR: fetched config looks incomplete:" >&2
      printf '%s\n' "$CONFIG" >&2
      exit 1
    fi

    echo "==> Installing config at $WG_CONF"
    mkdir -p "$(dirname "$WG_CONF")"
    umask 177
    printf '%s\n' "$CONFIG" > "$WG_CONF"

    echo "==> Connecting tunnel (sudo password may be required)"
    sudo wg-quick down "$TUNNEL" 2>/dev/null || true # clear any stale tunnel
    sudo wg-quick up "$TUNNEL"

    echo "==> Verifying exit IP"
    EXIT_IP=$(curl -s --max-time 20 ifconfig.me || true)
    if [ "$EXIT_IP" = "$PUBLIC_IP" ]; then
      echo "Connected. Traffic exits via $EXIT_IP. Enjoy the match!"
      echo "Afterwards: ./scripts/matchday.sh down"
    else
      echo "WARNING: exit IP is '$EXIT_IP', expected $PUBLIC_IP — check 'sudo wg show'." >&2
      exit 1
    fi
    ;;

  down)
    echo "==> Disconnecting tunnel"
    sudo wg-quick down "$TUNNEL" 2>/dev/null || true

    echo "==> terraform destroy"
    terraform destroy -auto-approve

    rm -f "$WG_CONF"
    echo "All AWS resources destroyed; local tunnel config removed. Cost is now \$0."
    ;;

  *)
    usage
    ;;
esac
