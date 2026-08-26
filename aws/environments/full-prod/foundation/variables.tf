variable "environment" {
  description = "Canonical environment owned by this foundation."
  type        = string
  default     = "full-prod"

  validation {
    condition     = var.environment == "full-prod"
    error_message = "This root builds full-prod only. Another environment name here would create a second cluster from full-prod's state key."
  }
}

variable "expected_account_id" {
  description = "AWS account allowed to receive the full-prod foundation."
  type        = string

  validation {
    condition     = var.expected_account_id == "916491575487"
    error_message = "Every reviewed MicroTodoSuite environment lives in account 916491575487."
  }
}

variable "aws_region" {
  description = "Region for full-prod. A transit gateway attachment is regional, so this must match the shared egress hub."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "full-prod must be in us-east-1, where the shared egress hub it attaches to lives."
  }
}

variable "owner" {
  description = "Owning team recorded in tags."
  type        = string
  default     = "platform"
}

variable "common_tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "Address space reserved for full-prod. Must not overlap any sibling spoke on the shared transit gateway."
  type        = string
  default     = "10.30.0.0/16"

  validation {
    condition     = var.vpc_cidr == "10.30.0.0/16"
    error_message = "full-prod owns 10.30.0.0/16 in the reviewed allocation. Overlapping a sibling spoke silently breaks transit routing rather than failing at apply."
  }
}

variable "availability_zones" {
  description = "Availability zones for full-prod."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnets. In transit-egress these carry load balancers only; no worker receives a public address."
  type        = list(string)
  default     = ["10.30.0.0/24", "10.30.1.0/24", "10.30.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private worker subnets. Each gets its own default route to the shared transit gateway."
  type        = list(string)
  default     = ["10.30.16.0/20", "10.30.32.0/20", "10.30.48.0/20"]
}

variable "outbound_mode" {
  description = "How private workloads reach the internet. full-prod uses the shared egress hub and creates no NAT gateway of its own."
  type        = string
  default     = "transit-egress"

  validation {
    condition     = var.outbound_mode == "transit-egress"
    error_message = "full-prod is a spoke of the shared egress hub. Switching it to direct-nat would add a NAT gateway and an Elastic IP that the fleet quota does not budget for."
  }
}

variable "transit_gateway_id" {
  description = "Shared transit gateway from the aws/shared/egress root's transit_gateway_id output."
  type        = string

  validation {
    condition     = var.transit_gateway_id != null && can(regex("^tgw-[0-9a-f]{8,17}$", var.transit_gateway_id))
    error_message = "full-prod uses transit egress and therefore requires a transit gateway id. Without one its private subnets would have no default route at all and every worker would come up with no path off-VPC."
  }
}

variable "single_nat_gateway" {
  description = "Unused in transit-egress; kept so the input surface matches the sibling roots."
  type        = bool
  default     = false
}

variable "cluster_public_access_cidrs" {
  description = "Operator addresses allowed to reach the public EKS endpoint. Exactly four reviewed host routes."
  type        = list(string)

  validation {
    condition     = length(var.cluster_public_access_cidrs) == 4
    error_message = "Exactly four reviewed operator addresses are approved for the control plane endpoint."
  }

  validation {
    condition     = alltrue([for cidr in var.cluster_public_access_cidrs : endswith(cidr, "/32")])
    error_message = "Every operator entry must be a single host route. A wider prefix admits addresses nobody reviewed."
  }

  validation {
    condition     = !contains(var.cluster_public_access_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 would expose the API server to the internet while endpoint_public_access still looked correctly configured."
  }
}

variable "bootstrap_admin_principal_arns" {
  description = "Principals granted cluster-admin during bootstrap."
  type        = list(string)
}

variable "bootstrap_node_instance_types" {
  description = "Instance types for the single bootstrap node."
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "bootstrap_node_ami_release_version" {
  description = "Pinned EKS-optimized AMI release for the bootstrap node."
  type        = string
  default     = "1.35.6-20260801"
}

variable "bootstrap_node_min_size" {
  description = "Floor of the bootstrap node group."
  type        = number
  default     = 1
}

variable "bootstrap_node_desired_size" {
  description = "Bootstrap capacity. One node: Karpenter provisions everything beyond it, so a larger managed group here is duplicated spend."
  type        = number
  default     = 1
}

variable "bootstrap_node_max_size" {
  description = "Ceiling of the bootstrap node group."
  type        = number
  default     = 2
}

variable "bootstrap_node_volume_size" {
  description = "Root volume size for the bootstrap node, in GiB."
  type        = number
  default     = 50
}

variable "iam_permissions_boundary_arn" {
  description = "Optional permissions boundary applied to roles this root creates."
  type        = string
  default     = null
}

variable "create_shared_resources" {
  description = "full-prod is a consumer. Every shared resource is owned by the dev owner root; creating them here would produce a second copy of an account-level singleton."
  type        = bool
  default     = false

  validation {
    condition     = var.create_shared_resources == false
    error_message = "full-prod must stay a consumer environment. Shared ECR, the GitHub OIDC provider, and the JWT secret containers are owned by aws/environments/dev/foundation."
  }
}

variable "shared_environments" {
  description = "Empty for a consumer: it creates no JWT secret containers."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.shared_environments) == 0
    error_message = "A consumer environment creates zero secret containers. It reads the owner's."
  }
}

variable "consumer_jwt_environment" {
  description = "The single environment whose JWT secret this cluster may read."
  type        = string
  default     = "prod"

  validation {
    condition     = var.consumer_jwt_environment == "prod"
    error_message = "full-prod reads the prod JWT secret only. Reading dev or staging would cross an environment boundary."
  }
}

variable "neutral_service_names" {
  description = "Services whose environment-neutral repositories this root references."
  type        = list(string)
  default     = ["auth-api", "frontend", "log-message-processor", "todos-api", "users-api"]
}

variable "github_oidc_subjects" {
  description = <<-EOT
    The five exact main-branch publisher subjects. A consumer creates neither the
    OIDC provider nor the publisher role, but the module still validates this
    inventory, so the value must stay identical across every root. Letting a
    consumer pass an empty or divergent set would make the exact-subject contract
    depend on which root you happened to read.
  EOT
  type        = list(string)
  default = [
    "repo:MicroTodoSuite/microservice-app-auth-api:ref:refs/heads/main",
    "repo:MicroTodoSuite/microservice-app-frontend:ref:refs/heads/main",
    "repo:MicroTodoSuite/microservice-app-log-message-processor:ref:refs/heads/main",
    "repo:MicroTodoSuite/microservice-app-todos-api:ref:refs/heads/main",
    "repo:MicroTodoSuite/microservice-app-users-api:ref:refs/heads/main",
  ]
}

variable "environment_jwt_secret_version" {
  description = "Unused by a consumer; kept so the input surface matches the sibling roots."
  type        = number
  default     = 1
}

variable "kyverno_service_account_subject" {
  description = "Kyverno admission controller ServiceAccount permitted to verify image signatures."
  type        = string
  default     = "system:serviceaccount:kyverno:kyverno-admission-controller"
}

variable "enable_full_profile_cluster_prerequisites" {
  description = "full-prod is a full-profile environment: EBS CSI, Karpenter, and the AWS Load Balancer Controller roles are all required."
  type        = bool
  default     = true

  validation {
    condition     = var.enable_full_profile_cluster_prerequisites == true
    error_message = "A full-profile environment without these prerequisites cannot scale past its single bootstrap node or serve ingress."
  }
}

variable "aws_load_balancer_controller_policy_arns" {
  description = <<-EOT
    Customer-managed policies attached to the AWS Load Balancer Controller IRSA
    role. Required, with no default: the policy is an account-level object created
    once from the upstream controller policy document, and defaulting it to a
    guessed ARN would produce a role that plans cleanly and then cannot create a
    load balancer at runtime.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.aws_load_balancer_controller_policy_arns) > 0
    error_message = "A full-profile environment needs at least one reviewed controller policy; the role must not exist without its permissions."
  }

  validation {
    condition = alltrue([
      for arn in var.aws_load_balancer_controller_policy_arns :
      can(regex("^arn:aws:iam::([0-9]{12}|aws):policy/.+$", arn))
    ])
    error_message = "Each entry must be an IAM policy ARN."
  }
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
