# Inputs of the eco/networking root. Values come from the gitignored eco.tfvars; the account
# is config/aws-account.env's AWS_ACCOUNT_ID (MTS-IAC-103).
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
  description = "Environment code, from MTS-IAC-101. This root is the economical environment's network."

  validation {
    condition     = var.environment == "eco"
    error_message = "This root builds the economical environment, eco."
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
  description = "The AWS region of the economical environment."

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
  description = "IPv4 CIDR block of the VPC, such as 10.10.0.0/16."

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 28
    error_message = "The VPC CIDR must be a valid IPv4 block between /16 and /28, the sizes AWS allows."
  }
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability Zones the VPC spans, one public and one private subnet and one NAT gateway in each; at least two, as EKS requires."

  validation {
    condition     = length(var.availability_zones) >= 2 && length(distinct(var.availability_zones)) == length(var.availability_zones) && alltrue([for zone in var.availability_zones : startswith(zone, var.aws_region) && can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+[a-z]$", zone))])
    error_message = "Give at least two distinct Availability Zones of aws_region, such as us-east-1a and us-east-1b."
  }
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks of the public subnets, in the order of availability_zones."

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.availability_zones) && alltrue([for cidr in var.public_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Give one valid IPv4 CIDR block per Availability Zone."
  }
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "IPv4 CIDR blocks of the private subnets, in the order of availability_zones."

  validation {
    condition     = length(var.private_subnet_cidrs) == length(var.availability_zones) && alltrue([for cidr in var.private_subnet_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Give one valid IPv4 CIDR block per Availability Zone."
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

variable "nat_gateways_enabled" {
  type        = bool
  description = "Whether each private subnet leaves through a NAT gateway in its zone. The lifecycle's down transition plans false, which removes only the NAT gateways, their Elastic IPs, and the private default routes."
  default     = true
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
