# The deletions a networking down plan makes beyond its egress. eco/networking, planned
# with nat_gateways_enabled=false, may delete only each NAT gateway, its Elastic IP, and
# the private default route through it. A full-profile spoke, planned with
# transit_enabled=false, may delete only its transit gateway attachment, the attachment's
# route table association, its two transit gateway routes, and the private default routes
# through the transit gateway. Any address printed here blocks the bundle.
.resource_changes[]?
| select(.change.actions | index("delete"))
| select(
    (.type == "aws_nat_gateway")
    or (.type == "aws_eip")
    or (.type == "aws_route" and (.address | test("\\.aws_route\\.private_(nat|transit)\\[[^]]+\\]$")))
    or (.type | test("^aws_ec2_transit_gateway_(vpc_attachment|route_table_association|route)$"))
    | not
  )
| .address
