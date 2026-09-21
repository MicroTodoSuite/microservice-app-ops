# Tags every taggable resource merges with its own Name tag; AzureRM has no
# default_tags (MTS-IAC-104).
locals {
  tags = merge(var.common_tags, var.additional_tags)
}
