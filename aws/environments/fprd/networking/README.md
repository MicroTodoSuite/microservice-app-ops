# fprd/networking

The full-production VPC is a transit-egress spoke of the shared `shd`
network. It creates three public subnets, three private transit subnets, one
internet gateway, and one dedicated transit attachment. It creates no NAT
gateway or Elastic IP: private workloads leave through the single reviewed NAT
gateway in the shared hub.

The root discovers the shared transit gateway, hub attachment, hub route table,
and fprd's dedicated route table by their standard `Name` tags. It also reads
the flow-log KMS key and IAM delivery role from `shd/security`; no shared
resource is owned by this state and no Terraform remote state is read.

The reviewed fprd allocation is `10.30.0.0/16`, with public `/24` and private
`/20` subnets in `us-east-1a`, `us-east-1b`, and `us-east-1c`. The private
subnets carry EKS, internal load balancer, and Karpenter discovery tags for the
subsequent `fprd/workload` root.

## Plan and apply

```bash
cp fprd.tfvars.example fprd.tfvars
cp networking.s3.tfbackend.example networking.s3.tfbackend
terraform -chdir=aws/environments/fprd/networking init -backend-config=networking.s3.tfbackend
terraform -chdir=aws/environments/fprd/networking plan -input=false -var-file=fprd.tfvars -out=fprd-networking.tfplan
```

Apply only the reviewed saved plan after the required state backup and human
approval. This root must be applied after `shd/networking` and before the
security and workload roots for fprd.

## Outputs

`vpc_id`, `vpc_cidr`, `public_subnet_ids`, `private_subnet_ids`,
`private_route_table_ids`, `nat_gateway_ids` (empty), `transit_gateway_id`,
`transit_attachment_id`, and `flow_log_group_arn`.
