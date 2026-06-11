# ---------------------------------------------------------------------------
# AMI — Amazon Linux 2023 ARM64, resolved dynamically (never hardcoded)
# ---------------------------------------------------------------------------

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------------------------------------------------------------------
# Minimal network: one VPC, one public subnet, one internet gateway.
# No NAT gateway, no load balancer, no VPC endpoints, no Elastic IP.
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.0.0/25"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security group — WireGuard UDP only. No SSH: shell access is via SSM
# Session Manager (outbound 443 from the instance, no inbound needed).
# ---------------------------------------------------------------------------

resource "aws_security_group" "wireguard" {
  name        = "${var.project_name}-sg"
  description = "WireGuard inbound, all outbound"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "WireGuard"
    from_port   = var.wg_port
    to_port     = var.wg_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"] # traveling: client IP is unpredictable
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

# ---------------------------------------------------------------------------
# IAM — instance profile with SSM Session Manager access only
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm" {
  name               = "${var.project_name}-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.ssm.name
}

# ---------------------------------------------------------------------------
# EC2 instance
# ---------------------------------------------------------------------------

resource "aws_instance" "wireguard" {
  ami                    = nonsensitive(data.aws_ssm_parameter.al2023_arm64.value)
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.wireguard.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  user_data = templatefile("${path.module}/user_data.yaml", {
    wg_port = var.wg_port
  })

  # IMDSv2 required
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-root"
    }
  }

  # -------------------------------------------------------------------------
  # OPTIONAL: Spot pricing (~70% cheaper per hour).
  # WARNING: AWS can reclaim spot capacity with only a 2-minute notice, which
  # would drop your VPN mid-match. Not recommended for live sports. If you
  # enable it, "persistent" + "stop" keeps start.sh/stop.sh working.
  # -------------------------------------------------------------------------
  # instance_market_options {
  #   market_type = "spot"
  #   spot_options {
  #     spot_instance_type             = "persistent"
  #     instance_interruption_behavior = "stop"
  #   }
  # }

  tags = {
    Name = "${var.project_name}-server"
  }

  lifecycle {
    # AL2023 AMIs are released frequently; don't replace a working VPN server
    # just because a newer AMI appeared. Comment out to pick up new AMIs.
    ignore_changes = [ami]
  }
}
