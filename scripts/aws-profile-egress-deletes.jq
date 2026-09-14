# The deletions an eco/networking down plan makes beyond its NAT egress. Planned with
# nat_gateways_enabled=false, the root deletes only each NAT gateway, its Elastic IP,
# and the private default route through it; any address printed here blocks the bundle.
.resource_changes[]?
| select(.change.actions | index("delete"))
| select(
    (.type == "aws_nat_gateway")
    or (.type == "aws_eip")
    or (.type == "aws_route" and (.address | test("\\.aws_route\\.private_nat\\[[^]]+\\]$")))
    | not
  )
| .address
