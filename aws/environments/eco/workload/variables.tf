# Inputs of the eco/workload root. Values come from the gitignored eco.tfvars; the account is
# config/aws-account.env's AWS_ACCOUNT_ID (MTS-IAC-103), and operator addresses live only there.
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
  description = "Environment code, from MTS-IAC-101. This root is the economical environment's workload."

  validation {
    condition     = var.environment == "eco"
    error_message = "This root builds the economical environment, eco."
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
  description = "The AWS region of the economical environment."

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

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor version of the control plane and the nodes, such as 1.35, in standard support."

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "The Kubernetes version must be a minor version such as 1.35."
  }
}

variable "service_ipv4_cidr" {
  type        = string
  description = "CIDR block of Kubernetes service addresses, fixed at creation: /24 to /12, inside 10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16, and outside the VPC."

  validation {
    condition     = can(cidrhost(var.service_ipv4_cidr, 0)) && try(tonumber(split("/", var.service_ipv4_cidr)[1]) >= 12 && tonumber(split("/", var.service_ipv4_cidr)[1]) <= 24, false)
    error_message = "The service CIDR must be a valid IPv4 block between /24 and /12."
  }
}

variable "endpoint_public_access_cidrs" {
  type        = list(string)
  description = "Operator CIDR blocks allowed to reach the public API endpoint, such as /32 addresses; [] keeps the API private. Real addresses belong only in the gitignored eco.tfvars."

  validation {
    condition     = alltrue([for cidr in var.endpoint_public_access_cidrs : can(cidrhost(cidr, 0)) && !endswith(cidr, "/0")])
    error_message = "Every public endpoint CIDR must be a valid IPv4 block narrower than /0; the API is never open to the whole internet."
  }
}

variable "cluster_admin_principal_arns" {
  type        = list(string)
  description = "IAM roles or users granted AmazonEKSClusterAdminPolicy through access entries, such as the Terraform deploy role. The managed node group's role needs none; Amazon EKS creates its entry."

  validation {
    condition     = length(var.cluster_admin_principal_arns) > 0 && length(distinct(var.cluster_admin_principal_arns)) == length(var.cluster_admin_principal_arns) && alltrue([for arn in var.cluster_admin_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/.+$", arn))])
    error_message = "Name at least one distinct IAM role or user ARN; an IAM principal can be in only one access entry."
  }
}

variable "control_plane_log_retention_in_days" {
  type        = number
  description = "Days the control-plane log group keeps its records."
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.control_plane_log_retention_in_days)
    error_message = "The retention must be one of the values CloudWatch Logs accepts; never-expire (0) is not offered."
  }
}

variable "cluster_deletion_protection" {
  type        = bool
  description = "Whether Amazon EKS refuses to delete the cluster. The lifecycle's down transition turns it off in a bundle of its own before the destroy bundle; the next plan of this root restores this value."
  default     = true
}

variable "addon_versions" {
  type = object({
    vpc_cni            = string
    kube_proxy         = string
    coredns            = string
    aws_ebs_csi_driver = string
    pod_identity_agent = string
  })
  description = "Pinned versions of the managed add-ons, each one aws eks describe-addon-versions lists for kubernetes_version."

  validation {
    condition     = alltrue([for version in values(var.addon_versions) : can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", version))])
    error_message = "Every add-on version must be pinned, such as v1.14.3-eksbuild.3."
  }
}

variable "node_release_version" {
  type        = string
  description = "Explicit AMI release of the bootstrap nodes, such as 1.35.6-20260818; raising it rolls the nodes."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9a-z]+$", var.node_release_version))
    error_message = "The node release version must be an explicit AMI release such as 1.35.6-20260818."
  }
}

variable "node_instance_types" {
  type        = list(string)
  description = "Instance types of the bootstrap node group, such as m7i-flex.large."

  validation {
    condition     = length(var.node_instance_types) >= 1 && length(var.node_instance_types) <= 20 && alltrue([for type in var.node_instance_types : can(regex("^[a-z0-9-]+\\.[a-z0-9]+$", type))])
    error_message = "Give 1 to 20 instance types such as m7i-flex.large."
  }
}

variable "node_scaling" {
  type = object({
    min_size     = number
    desired_size = number
    max_size     = number
  })
  description = "Bootstrap node counts: min_size <= desired_size <= max_size."

  validation {
    condition     = var.node_scaling.min_size >= 1 && var.node_scaling.min_size <= var.node_scaling.desired_size && var.node_scaling.desired_size <= var.node_scaling.max_size
    error_message = "The bootstrap group keeps at least one node, with min_size <= desired_size <= max_size."
  }
}

variable "node_root_volume_size_gib" {
  type        = number
  description = "Size in GiB of each bootstrap node's encrypted gp3 root volume."

  validation {
    condition     = var.node_root_volume_size_gib >= 20 && floor(var.node_root_volume_size_gib) == var.node_root_volume_size_gib
    error_message = "The root volume must be a whole number of GiB, at least 20."
  }
}

variable "public_zone_name" {
  type        = string
  description = "Domain of the canonical public hosted zone shd/dns created, microtodosuite.online; the economical host and its records live in it."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.public_zone_name))
    error_message = "The zone name must be a lowercase domain name without a trailing dot."
  }
}

variable "ingress_host" {
  type        = string
  description = "Host of the economical production environment, such as eco.microtodosuite.online; dev, staging, and demo are its subdomains <env>.<ingress_host>."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.ingress_host)) && endswith(var.ingress_host, ".${var.public_zone_name}")
    error_message = "The ingress host must be a lowercase subdomain of public_zone_name."
  }
}

variable "public_zone_delegation_verified" {
  type        = bool
  description = "Whether the registrar delegates public_zone_name to exactly the name servers of shd/dns's canonical zone (its canonical_zone_name_server_names output). The certificate and the address records wait for it (gitops spec 009 FR-044); an operator sets it to true only after verifying the delegation."
  default     = false
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
