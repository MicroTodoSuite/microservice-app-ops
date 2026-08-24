variable "environment" {
  description = "Canonical environment owned by this foundation."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must be a non-empty, DNS-safe string."
  }
}

variable "expected_account_id" {
  description = "AWS account that is allowed to receive this foundation."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must contain exactly 12 digits."
  }
}

variable "aws_region" {
  description = "AWS region for this foundation."
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

variable "bootstrap_admin_principal_arns" {
  description = "IAM role ARNs granted cluster-admin through EKS access entries."
  type        = set(string)

  validation {
    condition = length(var.bootstrap_admin_principal_arns) > 0 && alltrue([
      for arn in var.bootstrap_admin_principal_arns :
      can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:role/.+$", arn))
    ])
    error_message = "Provide at least one IAM role ARN; IAM users and STS session ARNs are not accepted."
  }
}

variable "availability_zones" {
  description = "Exactly three availability zones used by this foundation."
  type        = list(string)

  validation {
    condition = (
      length(var.availability_zones) == 3 &&
      length(distinct(var.availability_zones)) == 3 &&
      alltrue([for zone in var.availability_zones : startswith(zone, var.aws_region)])
    )
    error_message = "availability_zones must contain three unique zones in aws_region."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR dedicated to this environment's VPC."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && !strcontains(var.vpc_cidr, ":")
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "public_subnet_cidrs" {
  description = "One public subnet CIDR per selected availability zone."
  type        = list(string)

  validation {
    condition = (
      length(var.public_subnet_cidrs) == 3 &&
      length(distinct(var.public_subnet_cidrs)) == 3 &&
      alltrue([for cidr in var.public_subnet_cidrs : can(cidrnetmask(cidr)) && !strcontains(cidr, ":")])
    )
    error_message = "public_subnet_cidrs must contain three unique IPv4 CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "One private worker subnet CIDR per selected availability zone."
  type        = list(string)

  validation {
    condition = (
      length(var.private_subnet_cidrs) == 3 &&
      length(distinct(var.private_subnet_cidrs)) == 3 &&
      alltrue([for cidr in var.private_subnet_cidrs : can(cidrnetmask(cidr)) && !strcontains(cidr, ":")])
    )
    error_message = "private_subnet_cidrs must contain three unique IPv4 CIDRs."
  }
}

variable "cluster_public_access_cidrs" {
  description = "Allowed CIDR blocks for public EKS API access."
  type        = set(string)

  validation {
    condition     = alltrue([for c in var.cluster_public_access_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", c))])
    error_message = "cluster_public_access_cidrs must contain valid CIDR blocks."
  }
}

variable "bootstrap_node_instance_types" {
  description = "Approved non-burstable bootstrap node types with at least 2 vCPU and 8 GiB memory."
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "bootstrap_node_ami_release_version" {
  description = "Explicit AL2023 EKS AMI release for bootstrap nodes; upgrades require a dedicated reviewed change."
  type        = string
  default     = "1.35.6-20260801"
}

variable "bootstrap_node_min_size" {
  description = "Minimum number of stable bootstrap nodes."
  type        = number
  default     = 2
}

variable "bootstrap_node_desired_size" {
  description = "Desired number of stable bootstrap nodes."
  type        = number
  default     = 2
}

variable "bootstrap_node_max_size" {
  description = "Maximum number of stable bootstrap nodes."
  type        = number
  default     = 4
}

variable "bootstrap_node_volume_size" {
  description = "Encrypted gp3 root volume size in GiB for bootstrap nodes."
  type        = number
  default     = 50
}

variable "iam_permissions_boundary_arn" {
  description = "Optional IAM permissions boundary applied to foundation-created roles."
  type        = string
  default     = null
}

variable "shared_environments" {
  description = "Exact namespace environments sharing this EKS foundation. Can be empty for dedicated clusters."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.shared_environments : can(regex("^[a-z0-9-]+$", e))])
    error_message = "shared_environments elements must be DNS-safe strings."
  }
}

variable "neutral_service_names" {
  description = "Exact services published once to environment-neutral ECR repositories."
  type        = set(string)
  default = [
    "auth-api",
    "frontend",
    "log-message-processor",
    "todos-api",
    "users-api",
  ]
}

variable "github_oidc_subjects" {
  description = "Exact reviewed-main GitHub Actions subjects allowed to publish release artifacts."
  type        = set(string)
  default = [
    "repo:MicroTodoSuite/microservice-app-auth-api:ref:refs/heads/main",
    "repo:MicroTodoSuite/microservice-app-frontend:ref:refs/heads/main",
    "repo:MicroTodoSuite/microservice-app-log-message-processor:ref:refs/heads/main",
    "repo:MicroTodoSuite/microservice-app-todos-api:ref:refs/heads/main",
    "repo:MicroTodoSuite/microservice-app-users-api:ref:refs/heads/main",
  ]
}

variable "environment_jwt_secret_version" {
  description = "Monotonic write-only secret version. Increment only for an intentional JWT rotation."
  type        = number
  default     = 1
}

variable "kyverno_service_account_subject" {
  description = "Exact EKS ServiceAccount subject allowed to read private ECR signatures."
  type        = string
  default     = "system:serviceaccount:kyverno:kyverno-admission-controller"
}

locals {
  required_tags = {
    Project     = "MicroTodoSuite"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  tags = merge(var.common_tags, local.required_tags)
}
