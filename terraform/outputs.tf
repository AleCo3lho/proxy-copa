output "instance_id" {
  description = "EC2 instance ID (used by start.sh / stop.sh)."
  value       = aws_instance.wireguard.id
}

output "region" {
  description = "Deployment region (used by start.sh / stop.sh)."
  value       = var.region
}

output "public_ip" {
  description = "Public IP at apply time. This CHANGES after every stop/start — run ./start.sh to get the current IP and a refreshed client config."
  value       = aws_instance.wireguard.public_ip
}

output "get_client_config_command" {
  description = "Fetch the cloud-init console log containing the client config + QR code (allow ~3-5 min after first boot)."
  value       = "aws ec2 get-console-output --instance-id ${aws_instance.wireguard.id} --region ${var.region} --latest --output text"
}

output "ssm_session_command" {
  description = "Open a shell on the instance via SSM Session Manager (no SSH needed)."
  value       = "aws ssm start-session --target ${aws_instance.wireguard.id} --region ${var.region}"
}
