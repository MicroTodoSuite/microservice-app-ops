# Inputs of the shd/dns root. Values come from the gitignored shd.tfvars; the account is
# config/aws-account.env's AWS_ACCOUNT_ID (MTS-IAC-103).
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
  description = "Environment code, from MTS-IAC-101. The public zone is shared, so always shd."

  validation {
    condition     = var.environment == "shd"
    error_message = "The public zone belongs to the shared environment, shd."
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
  description = "The AWS region of the shared account-level resources."

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

variable "public_zone_name" {
  type        = string
  description = "Domain of the existing public hosted zone, such as microtodosuite.abrdns.com. It is adopted, never renamed: a new name replaces the zone and its name servers (ops spec 004 FR-005)."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.public_zone_name))
    error_message = "The zone name must be a lowercase domain name without a trailing dot."
  }
}

variable "public_zone_id" {
  type        = string
  description = "Hosted zone ID of the existing public zone, the ID the import block adopts."

  validation {
    condition     = can(regex("^Z[A-Z0-9]{1,31}$", var.public_zone_id))
    error_message = "The zone ID must be a Route 53 hosted zone ID such as Z1D633PJN98FT9, without the /hostedzone/ prefix."
  }
}

variable "canonical_zone_name" {
  type        = string
  description = "Domain of the canonical public hosted zone, microtodosuite.online (gitops spec 009 FR-044). The zone is created here; its name servers are set at the registrar by hand."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.canonical_zone_name))
    error_message = "The zone name must be a lowercase domain name without a trailing dot."
  }

  validation {
    condition     = var.canonical_zone_name != var.public_zone_name
    error_message = "The canonical zone must be a different domain from the adopted legacy zone; no new record may use the legacy domain (gitops spec 009 FR-044)."
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
