# Names and tags of the shd/dns root, built here and nowhere else (PC-IAC-012, PC-IAC-025).
locals {
  governance_prefix = "${var.client}-${var.project}-${var.environment}"

  public_zone_standard_name = "${local.governance_prefix}-dns-public"
  # The legacy root's comment, kept word for word so that adopting the zone changes only
  # its tags.
  public_zone_comment = "Public hosted zone for ${var.public_zone_name}; registrar delegation remains manual."

  # The canonical zone of gitops spec 009 FR-044, created here rather than adopted. Its name
  # servers are delegated at the registrar by hand, as the legacy zone's are.
  canonical_zone_standard_name = "${local.governance_prefix}-dns-canonical"
  canonical_zone_comment       = "Canonical public hosted zone for ${var.canonical_zone_name}; registrar delegation remains manual."

  # The destinations whose provider FQDN the operator has supplied, and the workload ones
  # among them that Route 53 health-checks. SonarQube is a tool, not a failover target.
  health_checked_destinations = {
    for key, fqdn in var.destination_provider_fqdns : key => fqdn if key != "sonar-full-dev"
  }

  # The common hostname's failover pair (gitops spec 009 T139): the AWS-production primary and
  # the Azure secondary, each served only while its own health check passes. Latency-based
  # active-active stays unavailable until a replicated data store exists.
  shared_hostname = "app.${var.canonical_zone_name}"
  shared_routing = {
    for failover, destination in { PRIMARY = "full-prod-aws", SECONDARY = "full-prod-azure" } :
    failover => destination if var.enable_active_active
  }

  common_tags = {
    Client      = var.client
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "terraform"
    Repository  = var.repository
  }
}
