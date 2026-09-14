# eco/networking

The economical environment's network, the first `eco` root in the PC-IAC-022
order (ops spec 004 T011, ai-agents specs/001 T025). It builds the VPC
through `network-v1.0.0`:

| Resource | Name |
| --- | --- |
| VPC | `lex-mts-eco-vpc-main` |
| Internet gateway | `lex-mts-eco-igw-main` |
| Public subnets, one per zone | `lex-mts-eco-sub-pub<zone letter>`, sharing `lex-mts-eco-rtb-public` |
| Private subnets, one per zone | `lex-mts-eco-sub-priv<zone letter>`, each with `lex-mts-eco-rtb-priv<zone letter>` |
| NAT gateways and Elastic IPs, one per zone, while `nat_gateways_enabled` | `lex-mts-eco-nat-<zone letter>`, `lex-mts-eco-eip-<zone letter>` |
| Flow log and its group | `lex-mts-eco-fl-main`, `/aws/vpc-flow-logs/lex-mts-eco-vpc-main` |

**Topology.** It is the one the legacy dev root ran:
- `10.10.0.0/16` over three zones;
- a `/24` public and a `/20` private subnet per zone;
- a NAT gateway per zone, so a zone's loss leaves the others their egress.

**NAT egress switch.** `nat_gateways_enabled` defaults to `true`. The
lifecycle's economical down transition plans it `false`, which removes the NAT
gateways, their Elastic IPs, and the private default routes. The VPC, subnets,
and route tables stay, because `eco/security`'s security groups belong to the
VPC. See `docs/aws-profile-lifecycle.md`.

**Subnet tags.** The subnets carry the discovery tags of the cluster
`lex-mts-eco-eks-main`, which `eco/workload` creates:
- public subnets: `kubernetes.io/role/elb`;
- private subnets: `kubernetes.io/role/internal-elb` and `karpenter.sh/discovery`.

**Flow logs.** They go to an encrypted group. The key and the delivery role
belong to `shd/security`, which must be applied first. This root finds them by
their standard names (`alias/lex-mts-shd-kms-flowlogs`,
`lex-mts-shd-role-flowlogs`). It creates no IAM or KMS resource.

**Zone check.** A zone name maps to a different zone ID in every account, and
EKS refuses cluster subnets in a few zone IDs. The plan therefore stops when a
listed zone resolves to one of those IDs.

## Plan and apply

```bash
cp eco.tfvars.example eco.tfvars                             # fill aws_account_id
cp networking.s3.tfbackend.example networking.s3.tfbackend   # fill from shd/state's outputs
terraform -chdir=aws/environments/eco/networking init -backend-config=networking.s3.tfbackend
terraform -chdir=aws/environments/eco/networking plan -input=false -var-file=eco.tfvars -out=eco-networking.tfplan
```

An apply uses only that saved plan, after the maintainer approves it
(MTS-IAC-107). The state key is new, so the apply records a `no-prior-state`
receipt.

## Outputs

`vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_subnet_ids`,
`nat_gateway_ids`, and `flow_log_group_arn`.
