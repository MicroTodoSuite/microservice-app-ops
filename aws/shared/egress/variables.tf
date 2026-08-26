variable "name" {
  description = "Name of the shared egress hub."
  type        = string
  default     = "microtodosuite-egress"
}

variable "expected_account_id" {
  description = "AWS account allowed to receive the shared egress hub."
  type        = string

  validation {
    condition     = var.expected_account_id == "916491575487"
    error_message = "The shared egress hub belongs to account 916491575487. Applying it elsewhere would create a second, unreviewed egress path rather than fail."
  }
}

variable "aws_region" {
  description = "Region for the shared egress hub. A transit gateway attachment is regional, so every spoke that uses this hub must live here too."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "Every reviewed MicroTodoSuite environment is in us-east-1; a hub in another region could not serve them."
  }
}

variable "vpc_cidr" {
  description = "CIDR of the egress VPC. Carries no workloads; holds the single NAT gateway and the hub side of the transit gateway."
  type        = string
  default     = "10.50.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for the egress VPC. Single-AZ by review: a second AZ means a second NAT gateway and a second Elastic IP."
  type        = list(string)
  default     = ["us-east-1a"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet holding the NAT gateway."
  type        = list(string)
  default     = ["10.50.0.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet holding the transit gateway attachment ENIs."
  type        = list(string)
  default     = ["10.50.16.0/20"]
}

variable "spokes" {
  description = <<-EOT
    Environments allowed to attach to the hub, keyed by spoke name, with each
    spoke's VPC CIDR. The hub creates one empty route table per entry; the
    attachment and both routes are owned by the spoke's own state.

    These are the three full-profile environments. The economical environments are
    deliberately absent: they keep their own in-VPC NAT egress and must not be
    made to depend on this shared hub, because the economical platform is the
    rollback target for the entire rollout.
  EOT
  type = map(object({
    vpc_cidr = string
  }))

  default = {
    "full-dev"     = { vpc_cidr = "10.40.0.0/16" }
    "full-staging" = { vpc_cidr = "10.20.0.0/16" }
    "full-prod"    = { vpc_cidr = "10.30.0.0/16" }
  }
}

variable "owner" {
  description = "Owning team recorded in tags."
  type        = string
  default     = "platform"
}

variable "common_tags" {
  description = "Tags applied to every resource in this root."
  type        = map(string)
  default     = {}
}
