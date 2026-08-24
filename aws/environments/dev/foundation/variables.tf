variable "expected_account_id" {
  description = "AWS account that is allowed to receive the dev foundation."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must contain exactly 12 digits."
  }
}

variable "aws_region" {
  description = "AWS region for the dev foundation."
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
  description = "Exactly three availability zones used by the dev foundation."
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
  description = "IPv4 CIDR dedicated to the dev VPC."
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
  description = "Human-approved dev-only public EKS API CIDR; staging and production require restricted policies."
  type        = set(string)

  validation {
    condition     = var.cluster_public_access_cidrs == toset(["0.0.0.0/0"])
    error_message = "The approved dev policy is exactly 0.0.0.0/0; changing it requires an explicit reviewed decision, and future environments must define restricted CIDRs."
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
  description = "Exact namespace environments sharing this EKS foundation."
  type        = set(string)
  default     = ["dev", "staging", "prod"]

  validation {
    condition     = var.shared_environments == toset(["dev", "staging", "prod"])
    error_message = "shared_environments must contain exactly dev, staging, and prod."
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

variable "observability_service_account_subject" {
  description = "Exact EKS ServiceAccount subject allowed to read the Alertmanager Slack webhook."
  type        = string
  default     = "system:serviceaccount:observability:observability-external-secrets-jwt"
}

variable "security_service_account_subject" {
  description = "Exact EKS ServiceAccount subject allowed to read the Falcosidekick Slack webhook."
  type        = string
  default     = "system:serviceaccount:security:security-external-secrets-jwt"
}

locals {
  required_tags = {
    Project     = "MicroTodoSuite"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  tags = merge(var.common_tags, local.required_tags)
}
