variable "name" {
  description = "Name of the centralized egress hub. Used for the VPC, transit gateway, route tables, KMS alias, and flow-log group."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.name))
    error_message = "name must be lowercase alphanumeric with hyphens, 3-41 characters, starting with a letter."
  }
}

variable "aws_region" {
  description = "Region that hosts the egress hub. Every spoke that uses this hub must live in the same region; a transit gateway attachment is regional."
  type        = string
}

variable "expected_account_id" {
  description = "Account that must own the egress hub. The hub is a shared singleton, so applying it into the wrong account is a reviewable failure rather than a silent duplicate."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id must be a 12-digit AWS account id."
  }
}

variable "vpc_cidr" {
  description = "CIDR of the egress VPC itself. It carries no workloads; it exists to hold the single NAT gateway and the hub side of the transit gateway."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR."
  }
}

variable "availability_zones" {
  description = "Availability zones for the egress VPC. The reviewed topology is deliberately single-AZ: a second AZ would add a second NAT gateway and a second Elastic IP. Widening this is an explicit cost and availability decision."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) == 1
    error_message = "The reviewed egress hub is single-AZ. Adding an availability zone changes the NAT/EIP count and must be re-reviewed, not defaulted."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs inside the egress VPC. Holds the NAT gateway."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 1
    error_message = "The single-AZ hub needs exactly one public subnet; more would imply more than one NAT gateway."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs inside the egress VPC. Holds the transit gateway attachment ENIs, which must not sit in the public subnet."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_cidrs) == 1
    error_message = "The single-AZ hub needs exactly one private subnet for its transit gateway attachment."
  }
}

variable "spokes" {
  description = <<-EOT
    Environments allowed to attach to this hub, keyed by spoke name, each with the
    spoke's VPC CIDR. The hub creates one empty route table per entry and nothing
    else: the attachment, the spoke's default route, and the spoke's return route
    are all owned by the spoke's own Terraform state. Removing an entry does not
    detach a live spoke; it only removes the table the spoke associates itself with,
    so remove the spoke's own attachment first.
  EOT
  type = map(object({
    vpc_cidr = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, spoke in var.spokes : can(cidrhost(spoke.vpc_cidr, 0))
    ])
    error_message = "Every spoke vpc_cidr must be a valid IPv4 CIDR."
  }

  validation {
    condition = alltrue([
      for key in keys(var.spokes) : can(regex("^[a-z][a-z0-9-]{1,30}$", key))
    ])
    error_message = "Spoke keys must be lowercase alphanumeric with hyphens; the key becomes part of the route table name a spoke looks itself up by."
  }

  # Two spokes whose CIDRs overlap cannot both be routed from the hub: the more
  # specific prefix silently wins and the other spoke's return traffic
  # disappears into it. Catch it here rather than from a black-hole route.
  validation {
    condition = alltrue(flatten([
      for a_key, a in var.spokes : [
        for b_key, b in var.spokes :
        a_key == b_key ? true : !(
          tonumber(split("/", a.vpc_cidr)[1]) <= tonumber(split("/", b.vpc_cidr)[1])
          ? cidrhost("${split("/", b.vpc_cidr)[0]}/${split("/", a.vpc_cidr)[1]}", 0) == cidrhost(a.vpc_cidr, 0)
          : cidrhost("${split("/", a.vpc_cidr)[0]}/${split("/", b.vpc_cidr)[1]}", 0) == cidrhost(b.vpc_cidr, 0)
        )
      ]
    ]))
    error_message = "Two spokes have overlapping VPC CIDRs. Overlapping spokes cannot be routed independently from the hub."
  }

  # A spoke that overlaps the hub's own VPC would make the hub's local route
  # shadow the spoke's return route.
  validation {
    condition = alltrue([
      for key, spoke in var.spokes : !(
        tonumber(split("/", var.vpc_cidr)[1]) <= tonumber(split("/", spoke.vpc_cidr)[1])
        ? cidrhost("${split("/", spoke.vpc_cidr)[0]}/${split("/", var.vpc_cidr)[1]}", 0) == cidrhost(var.vpc_cidr, 0)
        : cidrhost("${split("/", var.vpc_cidr)[0]}/${split("/", spoke.vpc_cidr)[1]}", 0) == cidrhost(spoke.vpc_cidr, 0)
      )
    ])
    error_message = "A spoke VPC CIDR overlaps the egress hub VPC CIDR. The hub's local route would shadow that spoke's return route."
  }
}

variable "flow_log_retention_in_days" {
  description = "Retention for the shared egress flow logs. These are the only record of what crossed the shared boundary."
  type        = number
  default     = 90

  validation {
    condition     = var.flow_log_retention_in_days >= 30
    error_message = "Shared egress flow logs must be retained for at least 30 days to remain useful as isolation evidence."
  }
}

variable "tags" {
  description = "Tags applied to every resource in the hub."
  type        = map(string)
  default     = {}
}
