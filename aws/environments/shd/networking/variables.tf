# Inputs of the shd/networking root. Values come from the gitignored shd.tfvars;
# account, region, every CIDR, and every zone remain operator inputs (T026).
variable "client" {
  type        = string
  description = "Client code, from MTS-IAC-101."

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.client))
    error_message = "The client code must be 2 to 10 lowercase letters or digits."
  }
}

variable "project" {
  type        = string
  description = "Project code, from MTS-IAC-101."

  validation {
    condition     = can(regex("^[a-z0-9]{2,15}$", var.project))
    error_message = "The project code must be 2 to 15 lowercase letters or digits."
  }
}

variable "environment" {
  type        = string
  description = "Environment code, from MTS-IAC-101. The centralized egress hub is always shd."

  validation {
    condition     = var.environment == "shd"
    error_message = "The centralized egress hub belongs to the shared environment, shd."
  }
}

variable "aws_account_id" {
  type        = string
  description = "The AWS account the root may act in: AWS_ACCOUNT_ID from config/aws-account.env."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "The AWS account ID must be exactly 12 digits."
  }
}

variable "aws_region" {
  type        = string
  description = "The AWS region of the shared egress hub and all of its transit spokes."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "The region must be an AWS region code such as us-east-1."
  }
}

variable "deploy_role_arn" {
  type        = string
  description = "ARN of the IAM role Terraform assumes to act in the account."

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.deploy_role_arn))
    error_message = "The deploy role must be an IAM role ARN."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "IPv4 CIDR block of the egress VPC."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 28
    error_message = "The VPC CIDR must be a valid IPv4 block between /16 and /28, the sizes AWS allows."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "The one Availability Zone of the deliberately single-AZ, single-NAT egress hub."

  validation {
    condition     = length(var.availability_zones) == 1 && startswith(var.availability_zones[0], var.aws_region) && can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+[a-z]$", var.availability_zones[0]))
    error_message = "Give exactly one Availability Zone of aws_region; widening the hub changes its reviewed cost model."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR block of the public subnet that holds the NAT gateway."

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones) && alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Give one valid public-subnet IPv4 CIDR block for the hub zone."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR block of the private subnet that holds the transit attachment."

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones) && alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Give one valid private-subnet IPv4 CIDR block for the hub zone."
  }
}

variable "spoke_vpc_cidrs" {
  type        = map(string)
  description = "VPC CIDR blocks of exactly the fdev, fstg, and fprd transit spokes."

  validation {
    condition     = toset(keys(var.spoke_vpc_cidrs)) == toset(["fdev", "fstg", "fprd"]) && alltrue([for cidr in values(var.spoke_vpc_cidrs) : can(cidrhost(cidr, 0))]) && length(distinct(values(var.spoke_vpc_cidrs))) == 3
    error_message = "Give distinct valid IPv4 CIDRs for exactly fdev, fstg, and fprd."
  }
}

variable "flow_log_retention_in_days" {
  type        = number
  description = "Days the VPC flow-log group keeps its records."
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_in_days)
    error_message = "The retention must be one of the values CloudWatch Logs accepts; never-expire (0) is not offered."
  }
}

variable "owner" {
  type        = string
  description = "Owning team, recorded in the Owner tag."
  default     = "platform"

  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "The owner must not be empty."
  }
}

variable "cost_center" {
  type        = string
  description = "Cost center the resources bill to, recorded in the CostCenter tag."
  default     = "microtodosuite"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,40}$", var.cost_center))
    error_message = "The cost center must be 2 to 40 lowercase letters, digits, or hyphens."
  }
}

variable "repository" {
  type        = string
  description = "Repository that manages the resources, recorded in the Repository tag."
  default     = "MicroTodoSuite/microservice-app-ops"

  validation {
    condition     = can(regex("^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$", var.repository))
    error_message = "The repository must be <owner>/<name>."
  }
}
