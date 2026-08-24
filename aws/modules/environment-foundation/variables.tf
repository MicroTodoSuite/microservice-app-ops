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

  validation {
    condition     = var.public_hosted_zone_name != "microtodosuite.online"
    error_message = "The canonical microtodosuite.online zone must be created through create_canonical_hosted_zone at its own resource address. Renaming this zone would replace it, destroying every record it holds and invalidating the registrar delegation."
  }
}

variable "create_canonical_hosted_zone" {
  description = "Whether this foundation owns the canonical microtodosuite.online public hosted zone. Exactly one foundation in the account may own it. Enabling it creates a NEW zone alongside public_hosted_zone_name and never renames, replaces, or destroys the legacy zone."
  type        = bool
  default     = false
}

variable "canonical_destination_records" {
  description = "Alias records to publish in the canonical zone, keyed by subdomain label. Empty by default: routing real traffic to app.microtodosuite.online requires a separate named traffic-owner approval taken after the DR game day."
  type = map(object({
    dns_name = string
    zone_id  = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for label, record in var.canonical_destination_records :
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", label)) &&
      trimspace(record.dns_name) != "" &&
      can(regex("^[A-Z0-9]+$", record.zone_id))
    ])
    error_message = "canonical_destination_records keys must be DNS labels and each value must carry a non-empty alias dns_name and a Route 53 hosted-zone id."
  }

  validation {
    condition     = length(var.canonical_destination_records) == 0 || var.create_canonical_hosted_zone
    error_message = "canonical_destination_records requires create_canonical_hosted_zone; a record cannot be published into a zone this foundation does not own."
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
  description = "Minimum number of stable bootstrap nodes. The current dev and demo foundations keep the default of 2; a reviewed cost-bounded full-profile cluster may lower it to 1."
  type        = number
  default     = 2

  validation {
    condition     = var.bootstrap_node_min_size >= 1 && floor(var.bootstrap_node_min_size) == var.bootstrap_node_min_size
    error_message = "bootstrap_node_min_size must be a whole number of at least 1; the bootstrap group hosts the GitOps controllers and cannot scale to zero."
  }
}

variable "bootstrap_node_desired_size" {
  description = "Desired number of stable bootstrap nodes. Must satisfy min <= desired <= max, which terraform_data.eks_input_guard enforces."
  type        = number
  default     = 2

  validation {
    condition     = var.bootstrap_node_desired_size >= 1 && floor(var.bootstrap_node_desired_size) == var.bootstrap_node_desired_size
    error_message = "bootstrap_node_desired_size must be a whole number of at least 1."
  }
}

variable "bootstrap_node_max_size" {
  description = "Maximum number of stable bootstrap nodes. Karpenter, not this managed group, provides elastic capacity on a full-profile cluster, so this ceiling stays deliberately small."
  type        = number
  default     = 4

  validation {
    condition     = var.bootstrap_node_max_size >= 1 && var.bootstrap_node_max_size <= 10 && floor(var.bootstrap_node_max_size) == var.bootstrap_node_max_size
    error_message = "bootstrap_node_max_size must be a whole number between 1 and 10; larger fleets belong to a reviewed Karpenter NodePool."
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

# ---------------------------------------------------------------------------
# Full-profile compatibility inputs (spec 009, T017/T018).
#
# Every switch below defaults to the value the current economical dev and demo
# foundations already use, so adding them changes no existing plan.
# ---------------------------------------------------------------------------

variable "outbound_mode" {
  description = "How private workloads reach the internet. direct-nat creates in-VPC NAT gateways and is what every current foundation uses. transit-egress creates no NAT gateway and no Elastic IP, and instead sends the private default route to a centrally owned transit gateway; the spoke keeps its own internet gateway for public load balancers only."
  type        = string
  default     = "direct-nat"

  validation {
    condition     = contains(["direct-nat", "transit-egress"], var.outbound_mode)
    error_message = "outbound_mode must be either direct-nat or transit-egress."
  }
}

variable "transit_gateway_id" {
  description = "Existing centrally owned transit gateway that provides egress when outbound_mode is transit-egress. This module never creates, owns, or attaches the transit gateway itself; that is the centralized egress account's resource."
  type        = string
  default     = null

  validation {
    condition     = var.transit_gateway_id == null || can(regex("^tgw-[0-9a-f]{8,17}$", var.transit_gateway_id))
    error_message = "transit_gateway_id must be null or a tgw- identifier."
  }

  validation {
    condition     = var.outbound_mode != "transit-egress" || var.transit_gateway_id != null
    error_message = "outbound_mode=transit-egress requires transit_gateway_id; this module never discovers or creates the transit gateway."
  }

  validation {
    condition     = var.outbound_mode == "transit-egress" || var.transit_gateway_id == null
    error_message = "transit_gateway_id must be null when outbound_mode is direct-nat, so a spoke cannot silently keep both egress paths."
  }
}

variable "enable_full_profile_cluster_prerequisites" {
  description = "Whether this cluster receives the opt-in full-profile IAM and event prerequisites: the Karpenter controller/node identities with their per-cluster encrypted interruption queue and EventBridge rules, and the AWS Load Balancer Controller IRSA role. Terraform owns only these prerequisites; GitOps owns both controllers and every Karpenter NodePool."
  type        = bool
  default     = false
}

variable "aws_load_balancer_controller_policy_arns" {
  description = "Reviewed IAM policy ARNs attached to the AWS Load Balancer Controller role. The controller's permission set is published by AWS and is deliberately not reproduced here: supply the exact policy the operator created and reviewed. Required when enable_full_profile_cluster_prerequisites is true."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for arn in var.aws_load_balancer_controller_policy_arns :
      can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::([0-9]{12}|aws):policy/.+$", arn))
    ])
    error_message = "aws_load_balancer_controller_policy_arns must contain IAM policy ARNs."
  }

  validation {
    condition     = !var.enable_full_profile_cluster_prerequisites || length(var.aws_load_balancer_controller_policy_arns) > 0
    error_message = "enable_full_profile_cluster_prerequisites requires at least one reviewed aws_load_balancer_controller_policy_arns entry; the role must not exist without its reviewed permissions."
  }
}

variable "karpenter_service_account_subject" {
  description = "Exact EKS service-account subject allowed to assume the Karpenter controller role."
  type        = string
  default     = "system:serviceaccount:kube-system:karpenter"

  validation {
    condition     = var.karpenter_service_account_subject == "system:serviceaccount:kube-system:karpenter"
    error_message = "karpenter_service_account_subject must identify only the kube-system Karpenter controller."
  }
}

variable "aws_load_balancer_controller_service_account_subject" {
  description = "Exact EKS service-account subject allowed to assume the AWS Load Balancer Controller role."
  type        = string
  default     = "system:serviceaccount:kube-system:aws-load-balancer-controller"

  validation {
    condition     = var.aws_load_balancer_controller_service_account_subject == "system:serviceaccount:kube-system:aws-load-balancer-controller"
    error_message = "aws_load_balancer_controller_service_account_subject must identify only the kube-system AWS Load Balancer Controller."
  }
}

variable "create_shared_resources" {
  description = "Whether this module instance owns the account-level neutral ECR repositories, GitHub Actions OIDC provider, shared IAM roles, and shared webhook secret containers."
  type        = bool
  default     = true
}

variable "additional_eks_oidc_issuers" {
  description = "Additional EKS OIDC issuers, keyed by a reviewed cluster label, whose service accounts may assume this foundation's SHARED reader roles. The full profile runs several clusters against one set of shared singletons; each extra issuer adds one exactly scoped trust statement rather than a second copy of the role. Empty by default, so no existing trust widens."
  type = map(object({
    provider_arn = string
    issuer_host  = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for label, issuer in var.additional_eks_oidc_issuers :
      can(regex("^[a-z0-9][a-z0-9-]*$", label)) &&
      can(regex("^oidc\\.eks\\.[a-z0-9-]+\\.amazonaws\\.com/id/[A-Z0-9]+$", issuer.issuer_host))
    ])
    error_message = "additional_eks_oidc_issuers keys must be DNS-safe cluster labels and issuer_host must be an EKS OIDC issuer of the form oidc.eks.<region>.amazonaws.com/id/<id>."
  }

  validation {
    condition = alltrue([
      for label, issuer in var.additional_eks_oidc_issuers :
      can(regex("^arn:(aws|aws-us-gov|aws-cn):iam::[0-9]{12}:oidc-provider/", issuer.provider_arn)) &&
      endswith(issuer.provider_arn, "/${issuer.issuer_host}")
    ])
    error_message = "Each additional_eks_oidc_issuers provider_arn must be an IAM OIDC provider ARN whose path is exactly its own issuer_host; a mismatch would trust one cluster's provider under another cluster's claims."
  }
}

variable "enable_platform_image_mirror" {
  description = "Whether the single microtodosuite/platform ECR mirror for third-party platform images is in use. The foundation that owns the shared resources creates it; every other foundation reads it. Off by default so no environment gains a repository before the stage that populates it."
  type        = bool
  default     = false
}

variable "github_platform_mirror_job_workflow_refs" {
  description = "Exact GitHub Actions job_workflow_ref values allowed to assume the platform mirror role, for example \"MicroTodoSuite/.github/.github/workflows/<file>.yml@refs/heads/main\". job_workflow_ref rather than sub binds the trust to one reviewed workflow file, so adding another workflow to the same repository grants nothing. Required when the owning foundation enables the mirror."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for ref in var.github_platform_mirror_job_workflow_refs :
      can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/.+\\.ya?ml@refs/(heads|tags)/.+$", ref))
    ])
    error_message = "Each github_platform_mirror_job_workflow_refs entry must be a fully qualified <owner>/<repo>/<path>.yml@refs/heads/<branch> workflow reference."
  }

  validation {
    condition     = !var.enable_platform_image_mirror || !var.create_shared_resources || length(var.github_platform_mirror_job_workflow_refs) > 0
    error_message = "The foundation that owns the platform mirror must name at least one exact workflow allowed to publish to it; the role must not exist with an unbounded trust."
  }
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

  # The canonical domain is fixed, not an operator input: the registrar
  # delegation and every downstream certificate are tied to this exact name.
  canonical_hosted_zone_name = "microtodosuite.online"

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
    ebs_csi    = "v1.64.0-eksbuild.1"
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
