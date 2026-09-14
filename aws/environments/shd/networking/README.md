# shd/networking

The shared networking root of the rebuilt layout (ops spec 004 T012,
ai-agents specs/001 T025 and T026). It replaces `aws/shared/egress` with the
domain layout and holds the centralized internet-egress hub used only by the
three full-profile environments.

The root composes two immutable module releases:

| Module | Responsibility |
| --- | --- |
| `network-v1.0.0` | Egress VPC, internet gateway, one public subnet, one private attachment subnet, one NAT gateway, one Elastic IP, and encrypted VPC flow logs |
| `transit-egress-v1.0.0` | Transit gateway, hub attachment, hub route table, and one empty isolated route table for each full-profile spoke |

The reviewed topology remains single-AZ and single-NAT. Its VPC retains
`10.50.0.0/16`; the full-development, full-staging, and full-production
spokes retain `10.40.0.0/16`, `10.20.0.0/16`, and `10.30.0.0/16`.
All CIDRs and the Availability Zone remain explicit `.tfvars` inputs.

The root reads the VPC flow-log key and delivery role from `shd/security` by
the standard names `alias/lex-mts-shd-kms-flowlogs` and
`lex-mts-shd-role-flowlogs`. It reads no Terraform remote state. Each spoke
later finds the transit gateway and route tables by their standard names and
owns its own attachment and routes, so the hub never manages a spoke resource.

## Plan and apply

```bash
cp shd.tfvars.example shd.tfvars                         # fill aws_account_id
cp networking.s3.tfbackend.example networking.s3.tfbackend
terraform -chdir=aws/environments/shd/networking init -backend-config=networking.s3.tfbackend
terraform -chdir=aws/environments/shd/networking plan -input=false -var-file=shd.tfvars -out=shd-networking.tfplan
```

The backend values come from `shd/state`. An apply uses only a reviewed saved
plan after the required state backup (MTS-IAC-107).

## Outputs

The root returns the egress VPC and subnet IDs, its one NAT and Elastic IP
allocation, its flow-log group ARN, the transit gateway ID and ARN, the hub
attachment and route table IDs, and the dedicated route table IDs of the three
spokes.
