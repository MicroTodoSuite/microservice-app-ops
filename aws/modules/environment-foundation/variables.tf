variable "project" {
  description = "Canonical project slug used in AWS resource names."
  type        = string
  default     = "microtodosuite"

  validation {
    condition     = var.project == "microtodosuite"
    error_message = "This module currently supports only project=microtodosuite."
  }
}

variable "environment" {
  description = "Canonical environment owned by this foundation."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must be a non-empty, DNS-safe string."
  }
}

variable "expected_account_id" {
  description = "AWS account that is allowed to receive this dev foundation."
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

variable "public_hosted_zone_name" {
  description = "Optional registered public DNS name whose Route 53 hosted zone is owned by this foundation."
  type        = string
  default     = null

  validation {
    condition = var.public_hosted_zone_name == null || (
      var.public_hosted_zone_name == trimspace(lower(var.public_hosted_zone_name)) &&
      length(var.public_hosted_zone_name) <= 253 &&
      !endswith(var.public_hosted_zone_name, ".") &&
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.public_hosted_zone_name))
    )
    error_message = "public_hosted_zone_name must be a lowercase fully qualified DNS name without a trailing dot."
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
  description = "Additional non-authoritative tags. Required governance tags cannot be overridden."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key in keys(var.common_tags) :
      !contains(["Project", "Environment", "ManagedBy", "Owner"], key)
    ])
    error_message = "common_tags cannot override Project, Environment, ManagedBy, or Owner."
  }
}

variable "bootstrap_admin_principal_arns" {
  description = "IAM role ARNs granted EKS cluster-admin access through EKS access entries."
  type        = set(string)

  validation {
    condition = length(var.bootstrap_admin_principal_arns) > 0 && alltrue([
      for arn in var.bootstrap_admin_principal_arns :
      can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:role/.+$", arn)) &&
      try(split(":", arn)[4] == var.expected_account_id, false)
    ])
    error_message = "Provide at least one IAM role ARN; IAM users and STS session ARNs are not accepted."
  }
}

variable "availability_zones" {
  description = "Exactly three availability zones used by the dev VPC and bootstrap node group."
  type        = list(string)

  validation {
    condition = (
      length(var.availability_zones) == 3 &&
      length(distinct(var.availability_zones)) == 3 &&
      alltrue([
        for zone in var.availability_zones :
        startswith(zone, var.aws_region) && can(regex("[a-z]$", zone))
      ])
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
  description = "One public IPv4 subnet CIDR for each selected availability zone."
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
  description = "One private worker IPv4 subnet CIDR for each selected availability zone."
  type        = list(string)

  validation {
    condition = (
      length(var.private_subnet_cidrs) == 3 &&
      length(distinct(var.private_subnet_cidrs)) == 3 &&
      alltrue([for cidr in var.private_subnet_cidrs : can(cidrnetmask(cidr)) && !strcontains(cidr, ":")]) &&
      length(setintersection(toset(var.public_subnet_cidrs), toset(var.private_subnet_cidrs))) == 0
    )
    error_message = "private_subnet_cidrs must contain three unique IPv4 CIDRs."
  }
}

variable "single_nat_gateway" {
  description = "Whether all private subnets share one NAT gateway instead of creating one NAT gateway per availability zone."
  type        = bool
  default     = false
}

variable "cluster_public_access_cidrs" {
  description = "Allowed CIDR blocks for public EKS API access."
  type        = set(string)

  validation {
    condition     = alltrue([for c in var.cluster_public_access_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", c))])
    error_message = "cluster_public_access_cidrs must contain valid CIDR blocks."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version validated with the GitOps add-on profile."
  type        = string
  default     = "1.35"

  validation {
    condition     = var.kubernetes_version == "1.35"
    error_message = "This foundation is validated only for Kubernetes 1.35."
  }
}

variable "bootstrap_node_instance_types" {
  description = "Account-compatible Free Tier bootstrap node types with at least 2 vCPU and 8 GiB memory."
  type        = list(string)
  default     = ["m7i-flex.large"]

  validation {
    condition = (
      length(var.bootstrap_node_instance_types) > 0 &&
      alltrue([
        for instance_type in var.bootstrap_node_instance_types :
        instance_type == "m7i-flex.large"
      ])
    )
    error_message = "bootstrap_node_instance_types must use the account-compatible m7i-flex.large 2-vCPU/8-GiB baseline."
  }
}

variable "bootstrap_node_ami_release_version" {
  description = "Explicit AL2023 EKS AMI release for bootstrap nodes; upgrades require a dedicated reviewed change."
  type        = string
  default     = "1.35.6-20260801"

  validation {
    condition     = can(regex("^1\\.35\\.[0-9]+-20[0-9]{6}$", var.bootstrap_node_ami_release_version))
    error_message = "bootstrap_node_ami_release_version must be an explicit Kubernetes 1.35 AL2023 release identifier."
  }
}

variable "bootstrap_node_min_size" {
  description = "Minimum number of stable bootstrap nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.bootstrap_node_min_size == 2
    error_message = "The dev bootstrap node minimum must remain 2."
  }
}

variable "bootstrap_node_desired_size" {
  description = "Desired number of stable bootstrap nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.bootstrap_node_desired_size == 2
    error_message = "The dev bootstrap node desired size must remain 2."
  }
}

variable "bootstrap_node_max_size" {
  description = "Maximum number of stable bootstrap nodes."
  type        = number
  default     = 4

  validation {
    condition     = var.bootstrap_node_max_size == 4
    error_message = "The dev bootstrap node maximum must remain 4."
  }
}

variable "bootstrap_node_volume_size" {
  description = "Encrypted gp3 root volume size in GiB for bootstrap nodes."
  type        = number
  default     = 50

  validation {
    condition     = var.bootstrap_node_volume_size >= 20
    error_message = "bootstrap_node_volume_size must be at least 20 GiB."
  }
}

variable "iam_permissions_boundary_arn" {
  description = "Optional IAM permissions boundary applied to foundation-created roles."
  type        = string
  default     = null

  validation {
    condition = (
      var.iam_permissions_boundary_arn == null ||
      can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:policy/.+$", var.iam_permissions_boundary_arn))
    )
    error_message = "iam_permissions_boundary_arn must be null or an IAM policy ARN."
  }
}

variable "create_shared_resources" {
  description = "Whether this module instance owns the account-level neutral ECR repositories, GitHub Actions OIDC provider, shared IAM roles, and shared webhook secret containers."
  type        = bool
  default     = true
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
  description = "Exact services published once to environment-neutral repositories."
  type        = set(string)
  default = [
    "auth-api",
    "frontend",
    "log-message-processor",
    "todos-api",
    "users-api",
  ]

  validation {
    condition = var.neutral_service_names == toset([
      "auth-api",
      "frontend",
      "log-message-processor",
      "todos-api",
      "users-api",
    ])
    error_message = "neutral_service_names must contain the five exact business services."
  }
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

  validation {
    condition = var.github_oidc_subjects == toset([
      "repo:MicroTodoSuite/microservice-app-auth-api:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-frontend:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-log-message-processor:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-todos-api:ref:refs/heads/main",
      "repo:MicroTodoSuite/microservice-app-users-api:ref:refs/heads/main",
    ])
    error_message = "github_oidc_subjects must contain only the five exact main-branch subjects."
  }
}

variable "environment_jwt_secret_version" {
  description = "Monotonic write-only secret version. Increment only for an intentional JWT rotation."
  type        = number
  default     = 1

  validation {
    condition     = var.environment_jwt_secret_version >= 1 && floor(var.environment_jwt_secret_version) == var.environment_jwt_secret_version
    error_message = "environment_jwt_secret_version must be a positive integer."
  }
}

variable "environment_jwt_values" {
  description = "Ephemeral JWT values generated by the composition root and consumed only by write-only arguments."
  type        = map(string)
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = toset(keys(var.environment_jwt_values)) == var.shared_environments
    error_message = "environment_jwt_values must contain exactly one ephemeral value per shared environment."
  }
}

variable "kyverno_service_account_subject" {
  description = "Exact EKS service-account subject allowed to read private ECR signatures."
  type        = string
  default     = "system:serviceaccount:kyverno:kyverno-admission-controller"

  validation {
    condition     = var.kyverno_service_account_subject == "system:serviceaccount:kyverno:kyverno-admission-controller"
    error_message = "kyverno_service_account_subject must identify only the admission controller."
  }
}

variable "observability_service_account_subject" {
  description = "Exact EKS service-account subject allowed to read the Alertmanager Slack webhook."
  type        = string
  default     = "system:serviceaccount:observability:observability-external-secrets-jwt"

  validation {
    condition     = var.observability_service_account_subject == "system:serviceaccount:observability:observability-external-secrets-jwt"
    error_message = "observability_service_account_subject must identify only the observability namespace's External Secrets ServiceAccount."
  }
}

variable "security_service_account_subject" {
  description = "Exact EKS service-account subject allowed to read the Falcosidekick Slack webhook."
  type        = string
  default     = "system:serviceaccount:security:security-external-secrets-jwt"

  validation {
    condition     = var.security_service_account_subject == "system:serviceaccount:security:security-external-secrets-jwt"
    error_message = "security_service_account_subject must identify only the security namespace's External Secrets ServiceAccount."
  }
}

locals {
  cluster_name = "${var.project}-${var.environment}"

  service_names = toset([
    "auth-api",
    "frontend",
    "log-message-processor",
    "todos-api",
    "users-api",
  ])

  addon_versions = {
    coredns    = "v1.14.3-eksbuild.3"
    kube_proxy = "v1.35.3-eksbuild.18"
    vpc_cni    = "v1.23.0-eksbuild.1"
  }

  required_tags = {
    Project     = "MicroTodoSuite"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  tags = merge(var.common_tags, local.required_tags)
}

resource "terraform_data" "eks_input_guard" {
  input = {
    administrator_roles = var.bootstrap_admin_principal_arns
    cluster_name        = local.cluster_name
    kubernetes_version  = var.kubernetes_version
  }

  lifecycle {
    precondition {
      condition = (
        var.bootstrap_node_min_size <= var.bootstrap_node_desired_size &&
        var.bootstrap_node_desired_size <= var.bootstrap_node_max_size
      )
      error_message = "Bootstrap node sizes must satisfy min <= desired <= max."
    }
  }
}
