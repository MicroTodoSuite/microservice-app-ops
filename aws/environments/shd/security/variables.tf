# Inputs of the shd/security root. Values come from the gitignored shd.tfvars; the account is
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
  description = "Environment code, from MTS-IAC-101. Account-level security is always shd."

  validation {
    condition     = var.environment == "shd"
    error_message = "Account-level security belongs to the shared environment, shd."
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

variable "github_organization" {
  type        = string
  description = "GitHub organization whose main-branch workflows may publish images (ai-agents specs/001 T026)."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,38}$", var.github_organization))
    error_message = "The GitHub organization must be 1 to 39 letters, digits, or hyphens."
  }
}

variable "image_publisher_repositories" {
  type        = list(string)
  description = "Repositories of github_organization whose main-branch workflows may push service images."

  validation {
    condition     = length(var.image_publisher_repositories) > 0 && alltrue([for repository in var.image_publisher_repositories : can(regex("^[A-Za-z0-9._-]{1,100}$", repository))])
    error_message = "Give at least one repository name of letters, digits, dots, underscores, or hyphens."
  }
}

variable "service_image_keys" {
  type        = list(string)
  description = "Keys of the service image repositories shd/registry creates, such as authapi; each becomes lex-mts-shd-ecr-<key>."

  validation {
    condition     = length(var.service_image_keys) > 0 && alltrue([for key in var.service_image_keys : can(regex("^[a-z0-9]{1,10}$", key))])
    error_message = "Every key must be 1 to 10 lowercase letters or digits (MTS-IAC-101)."
  }
}

variable "deploy_role_operator_arns" {
  type        = list(string)
  description = "IAM users or roles of the operators allowed to assume the Terraform deploy role, always with MFA. Real ARNs belong only in the gitignored shd.tfvars."

  validation {
    condition     = length(var.deploy_role_operator_arns) > 0 && length(distinct(var.deploy_role_operator_arns)) == length(var.deploy_role_operator_arns) && alltrue([for arn in var.deploy_role_operator_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(user|role)/[A-Za-z0-9+=,.@_/-]+$", arn))])
    error_message = "Name at least one distinct IAM user or role ARN."
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
