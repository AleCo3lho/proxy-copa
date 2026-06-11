variable "region" {
  description = "AWS region to deploy in. Pick the region of your home country, e.g. eu-west-2 (London) for UK streaming services."
  type        = string
  default     = "sa-east-1"
}

variable "instance_type" {
  description = "EC2 instance type. t4g.small (ARM/Graviton) is one of the cheapest types and its baseline network bandwidth comfortably covers sustained 30 Mbps 4K streaming."
  type        = string
  default     = "t4g.small"
}

variable "wg_port" {
  description = "UDP port WireGuard listens on."
  type        = number
  default     = 51820
}

variable "project_name" {
  description = "Name used for resource names and the Project cost-tracking tag."
  type        = string
  default     = "proxy-copa"
}
