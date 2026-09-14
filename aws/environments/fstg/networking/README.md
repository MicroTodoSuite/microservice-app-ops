# fstg/networking

The full-staging VPC is a transit-egress spoke of the shared `shd`
network. It creates three public subnets, three private transit subnets, one
internet gateway, and one dedicated transit attachment. It creates no NAT
gateway or Elastic IP: private workloads leave through the single reviewed NAT
gateway in the shared hub.

The root discovers the shared transit gateway, hub attachment, hub route table,
and fstg's dedicated route table by their standard `Name` tags. It also reads
the flow-log KMS key and IAM delivery role from `shd/security`; no shared
resource is owned by this state and no Terraform remote state is read.

The reviewed fstg allocation is `10.20.0.0/16`, with public `/24` and private
`/20` subnets in `us-east-1a`, `us-east-1b`, and `us-east-1c`. The private
subnets carry EKS, internal load balancer, and Karpenter discovery tags for the
subsequent `fstg/workload` root.

**Transit switch.** `transit_enabled` defaults to `true`. The lifecycle's full
down transition plans it `false`: the attachment, its route table association,
its transit routes, and the private default routes go, while the VPC, subnets,
and route tables stay, because `fstg/security`'s security groups belong to the
VPC. With transit off the root reads nothing from the hub, so the hub can be
destroyed after it. See `docs/aws-profile-lifecycle.md`.

## Plan and apply

```bash
cp fstg.tfvars.example fstg.tfvars
cp networking.s3.tfbackend.example networking.s3.tfbackend
terraform -chdir=aws/environments/fstg/networking init -backend-config=networking.s3.tfbackend
terraform -chdir=aws/environments/fstg/networking plan -input=false -var-file=fstg.tfvars -out=fstg-networking.tfplan
```

Apply only the reviewed saved plan after the required state backup and human
approval. This root must be applied after `shd/networking` and before the
security and workload roots for fstg.

## Outputs

`vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_subnet_ids`,
`private_route_table_ids`, `nat_gateway_ids` (empty), `transit_gateway_id`,
`transit_attachment_id`, and `flow_log_group_arn`.
