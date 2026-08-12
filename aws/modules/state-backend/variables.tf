variable "project" {
  description = "Canonical project slug."
  type        = string
  default     = "microtodosuite"

  validation {
    condition     = var.project == "microtodosuite"
    error_message = "This module currently supports only project=microtodosuite."
  }
}

variable "environment" {
  description = "Canonical environment owned by the backend."
  type        = string
  default     = "dev"

  validation {
    condition     = var.environment == "dev"
    error_message = "This feature is dev-only."
  }
}

variable "expected_account_id" {
  description = "AWS account that is allowed to own this backend."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must contain exactly 12 digits."
  }
}

variable "aws_region" {
  description = "AWS region for the backend."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier."
  }
}

variable "owner" {
  description = "Owning team recorded on all taggable resources."
  type        = string
  default     = "Platform"

  validation {
    condition     = trimspace(var.owner) != ""
    error_message = "owner must not be empty."
  }
}

variable "common_tags" {
  description = "Additional non-authoritative tags."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key in keys(var.common_tags) :
      !contains(["Project", "Environment", "ManagedBy", "Owner"], key)
    ])
    error_message = "common_tags cannot override required governance tags."
  }
}

locals {
  bucket_name = "${var.project}-tfstate-${var.expected_account_id}-${var.aws_region}-${var.environment}"

  foundation_state_key = "environments/${var.environment}/foundation/terraform.tfstate"
  bootstrap_state_key  = "environments/${var.environment}/backend-bootstrap/terraform.tfstate"
  foundation_lock_key  = "${local.foundation_state_key}.tflock"

  required_tags = {
    Project     = "MicroTodoSuite"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  tags = merge(var.common_tags, local.required_tags)
}
