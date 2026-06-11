# proxy-copa — personal WireGuard VPN on AWS

Spins up a small EC2 instance running WireGuard, connects your machine to it,
and tears everything down when you're done — so you only pay while you watch.

## Dependencies

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) + [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- WireGuard (`brew install wireguard-tools`)

## Usage

In a shell with your AWS credentials configured:

```sh
./scripts/matchday.sh up      # spin up and connect the VPN
./scripts/matchday.sh down    # disconnect and destroy everything
```

`up` takes ~5 minutes (cloud-init has to install WireGuard on the instance).
When it finishes, all your traffic exits through AWS — done, enjoy the match.

Alternative: keep the instance and stop/start it between uses instead of
destroying it (`./scripts/start.sh` / `./scripts/stop.sh`). The public IP
changes on every start; `start.sh` prints the updated config + QR code.

## Layout

- `terraform/` — VPC, EC2 instance, security group, cloud-init WireGuard setup
- `scripts/` — the helpers above

## Cost

Pennies per match for compute. Data transfer is the real cost: first
100 GB/month is free, after that ~$2 per 2-hour 4K match. `matchday.sh down`
brings the bill to $0 between games.
