# Inputs of the fprd/security-irsa root. Values come from the gitignored fprd.tfvars; the account
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
  description = "Environment code, from MTS-IAC-101. This root is the full production environment's IRSA pass."

  validation {
    condition     = var.environment == "fprd"
    error_message = "This root builds the full production environment, fprd."
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
  description = "The AWS region of the full production environment."

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

variable "jwt_reader_namespaces" {
  type        = map(string)
  description = "Kubernetes namespace of each application environment, keyed by its three-letter code, such as dev = microtodo-dev; its external-secrets-jwt service account reads <client>-<project>-fprd-sm-jwt<code>."

  validation {
    condition     = length(var.jwt_reader_namespaces) > 0 && alltrue([for code, namespace in var.jwt_reader_namespaces : can(regex("^[a-z]{3}$", code)) && can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", namespace))])
    error_message = "Key every namespace by a three-letter lowercase code, and give each a Kubernetes namespace name."
  }
}

variable "service_image_keys" {
  type        = list(string)
  description = "Keys of the shared service image repositories shd/registry creates, such as authapi; Trivy Operator and Kyverno read <client>-<project>-shd-ecr-<key>."

  validation {
    condition     = length(var.service_image_keys) > 0 && length(distinct(var.service_image_keys)) == length(var.service_image_keys) && alltrue([for key in var.service_image_keys : can(regex("^[a-z0-9]{1,10}$", key))])
    error_message = "Give distinct keys of 1 to 10 lowercase letters or digits (MTS-IAC-101)."
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
