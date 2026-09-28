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

variable "manage_legacy_public_dns" {
  type        = bool
  description = "Whether this root manages the legacy public hosted zone. False omits it; true enables the existing adoption path."
  default     = false

  validation {
    condition     = var.manage_legacy_public_dns != null
    error_message = "The legacy public-zone management choice must be true or false, not null."
  }
}

variable "public_zone_name" {
  type        = string
  description = "Domain of the optional legacy public hosted zone, such as microtodosuite.abrdns.com. When managed, it is adopted and never renamed: a new name replaces the zone and its name servers (ops spec 004 FR-005)."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.public_zone_name))
    error_message = "The zone name must be a lowercase domain name without a trailing dot."
  }
}

variable "public_zone_id" {
  type        = string
  description = "Hosted zone ID to adopt when adopt_existing_public_dns is true; null when adoption is disabled."

  validation {
    condition     = var.adopt_existing_public_dns ? can(regex("^Z[A-Z0-9]{1,31}$", var.public_zone_id)) : var.public_zone_id == null
    error_message = "Set public_zone_id to a Route 53 hosted zone ID without the /hostedzone/ prefix when adoption is enabled; leave it null when Terraform creates the zone."
  }
}

variable "adopt_existing_public_dns" {
  type        = bool
  description = "Whether to adopt the managed legacy public hosted zone by public_zone_id. This must be false when legacy-zone management is disabled."
  default     = false

  validation {
    condition     = var.adopt_existing_public_dns != null
    error_message = "The public DNS adoption choice must be true or false, not null."
  }

  validation {
    condition     = !var.adopt_existing_public_dns || var.manage_legacy_public_dns
    error_message = "Legacy public DNS adoption requires manage_legacy_public_dns to be true."
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

variable "destination_provider_fqdns" {
  type        = map(string)
  description = "Reviewed provider FQDN of each live destination, keyed by its subdomain in the canonical zone: full-dev, full-staging, full-prod-aws, full-prod-azure, or sonar-full-dev (gitops spec 009 T134). Each key present creates its CNAME, and each workload destination its HTTPS health check; the empty default creates none."
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for key in keys(var.destination_provider_fqdns) : contains(["full-dev", "full-staging", "full-prod-aws", "full-prod-azure", "sonar-full-dev"], key)])
    error_message = "Key each provider FQDN by full-dev, full-staging, full-prod-aws, full-prod-azure, or sonar-full-dev."
  }

  validation {
    condition     = alltrue([for fqdn in values(var.destination_provider_fqdns) : length(fqdn) <= 253 && can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", fqdn))])
    error_message = "Every provider FQDN must be a non-empty lowercase domain name without a trailing dot; a missing or malformed target fails the plan rather than publishing a broken record."
  }

  validation {
    condition     = alltrue([for fqdn in values(var.destination_provider_fqdns) : fqdn != var.canonical_zone_name && !endswith(fqdn, ".${var.canonical_zone_name}")])
    error_message = "A provider FQDN is the destination's own endpoint, never a name inside the canonical zone."
  }
}

variable "enable_active_active" {
  type        = bool
  description = "Whether app.<canonical zone> routes by health-evaluated failover between the AWS-production primary and the Azure secondary. Only T139's separately approved plan turns it on (gitops spec 009 T140)."
  default     = false

  validation {
    condition     = var.enable_active_active != null
    error_message = "The shared routing choice must be true or false, not null."
  }

  validation {
    condition     = !var.enable_active_active || alltrue([for key in ["full-prod-aws", "full-prod-azure"] : contains(keys(var.destination_provider_fqdns), key)])
    error_message = "Shared routing needs both production destinations, full-prod-aws and full-prod-azure, and their health checks."
  }
}
