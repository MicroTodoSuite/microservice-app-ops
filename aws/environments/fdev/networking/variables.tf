# Inputs of the fdev/networking root. Account, region, zones, and CIDRs are
# operator inputs; names and transit identifiers are derived or discovered.
variable "client" {
  type        = string
  description = "Client code from MTS-IAC-101."

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.client))
    error_message = "The client code must be 2 to 10 lowercase letters or digits."
  }
}

variable "project" {
  type        = string
  description = "Project code from MTS-IAC-101."

  validation {
    condition     = can(regex("^[a-z0-9]{2,15}$", var.project))
    error_message = "The project code must be 2 to 15 lowercase letters or digits."
  }
}

variable "environment" {
  type        = string
  description = "Canonical environment owned by this root."

  validation {
    condition     = var.environment == "fdev"
    error_message = "This root builds fdev only. Another environment would create a second spoke from fdev's state key."
  }
}

variable "aws_account_id" {
  type        = string
  description = "AWS account the root may act in, from config/aws-account.env."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "The AWS account ID must be exactly 12 digits."
  }
}

variable "aws_region" {
  type        = string
  description = "Region shared by the hub and every full-profile spoke."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "The region must be an AWS region code such as us-east-1."
  }
}

variable "deploy_role_arn" {
  type        = string
  description = "IAM role ARN Terraform assumes to act in the account."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.deploy_role_arn))
    error_message = "The deploy role must be an IAM role ARN."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 address space reserved for the fdev spoke."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 28
    error_message = "The VPC CIDR must be a valid IPv4 block between /16 and /28."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Exactly three Availability Zones used by the full-profile cluster."

  validation {
    condition     = length(var.availability_zones) == 3 && length(distinct(var.availability_zones)) == 3 && alltrue([for zone in var.availability_zones : startswith(zone, var.aws_region) && can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+[a-z]$", zone))])
    error_message = "Give exactly three distinct Availability Zones of aws_region."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "One public subnet CIDR per Availability Zone, in the same order."

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones) && alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Give one valid public subnet CIDR per Availability Zone."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "One private transit subnet CIDR per Availability Zone, in the same order."

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones) && alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Give one valid private subnet CIDR per Availability Zone."
  }
}

variable "flow_log_retention_in_days" {
  type        = number
  description = "Days the VPC flow-log group keeps its records."
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_in_days)
    error_message = "The retention must be one of the values CloudWatch Logs accepts."
  }
}

variable "transit_enabled" {
  type        = bool
  description = "Whether the private subnets leave through the shared hub's transit gateway. The lifecycle's full down transition plans false, which removes only this spoke's attachment, its route table association, its transit routes, and the private default routes, and reads nothing from the hub."
  default     = true
}

variable "owner" {
  type        = string
  description = "Owning team recorded in tags."
  default     = "platform"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "The owner must not be empty."
  }
}

variable "cost_center" {
  type        = string
  description = "Cost center recorded in tags."
  default     = "microtodosuite"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,40}$", var.cost_center))
    error_message = "The cost center must be 2 to 40 lowercase letters, digits, or hyphens."
  }
}

variable "repository" {
  type        = string
  description = "Repository recorded in tags."
  default     = "MicroTodoSuite/microservice-app-ops"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.repository))
    error_message = "The repository must be <owner>/<name>."
  }
}
