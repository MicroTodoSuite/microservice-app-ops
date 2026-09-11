# Implementation Plan: Naming-Convention Adoption and Infrastructure Rebuild

## Inventory — deployed on 2026-09-11 (read-only API calls)

**Re-verified 2026-09-11 15:20 UTC.** Every item below is still deployed: the
cluster and node group are `ACTIVE`, the three NAT gateways `available`, both
instances running since 2026-09-07, the six secrets present and not scheduled
for deletion, all 18 images in ECR, and CloudTrail shows no delete or terminate
event in the preceding 24 hours. The preservation phase can therefore run in
full before the window.

Physical names use the client code `lex` (Lexfield Legal); the first draft used
`gcs`, corrected by the maintainer on 2026-09-11.

| Current | Kind | New name | Treatment |
| --- | --- | --- | --- |
| `microtodosuite-dev` | EKS cluster, Kubernetes 1.35 | `lex-mts-eco-eks-main` | Recreate |
| `bootstrap-35e466b0…` | Node group, 2 × `m7i-flex.large` | `lex-mts-eco-ng-bootstrap` | Recreate |
| `aws-ebs-csi-driver`, `coredns`, `kube-proxy`, `vpc-cni` | EKS add-ons | same add-on names | Recreate with the cluster |
| `microtodosuite-dev` | VPC `10.10.0.0/16` | `lex-mts-eco-vpc-main` | Recreate |
| 6 subnets, 5 route tables, 1 IGW, 3 NAT, 3 EIP, NACL, flow log | Network | `lex-mts-eco-{sub,rtb,igw,nat,eip,fl}-…` | Recreate |
| default VPC `172.31.0.0/16` | Network, not Terraform | — | Delete (capacity limit L1) |
| 5 security groups | Security | `lex-mts-eco-sg-cluster`, `-node`; EKS-created group unchanged | Recreate |
| `microtodosuite-dev-node`, `-dev-cluster-…`, `-dev-ebs-csi`, `-dev-vpc-cni` | IAM roles | `lex-mts-eco-role-{node,cluster,ebscsi,vpccni}` | Recreate |
| `microtodosuite-{dev,staging,prod,demo}-jwt-reader` | IRSA roles | `lex-mts-eco-role-jwt{dev,stg,prd,dmo}` | Recreate |
| `microtodosuite-observability-secrets-reader`, `-security-secrets-reader` | IRSA roles | `lex-mts-eco-role-obssecret`, `-secsecret` | Recreate |
| `microtodosuite-github-ecr-publisher` | IAM role | `lex-mts-shd-role-ecrpublish` | Recreate |
| `microtodosuite-kyverno-ecr-verifier` | IAM role | `lex-mts-shd-role-kyvernoecr` | Recreate |
| `microtodosuite-terraform-dev` | Deploy role | `lex-mts-shd-role-tfdeploy` | Create first, retire last |
| 2 customer policies | IAM | `lex-mts-eco-pol-…` | Recreate |
| EKS OIDC provider | IAM | issuer URL | Recreate with the cluster |
| GitHub OIDC provider | IAM | issuer URL | **Keep**; import into `shd/security` |
| `microtodosuite-tfstate-575172595729-us-east-1-dev` | S3 state bucket | `lex-mts-shd-s3-tfstate-575172595729` | New bucket; old one archived, then deleted |
| `alias/microtodosuite-tfstate-…`, `alias/eks/microtodosuite-dev`, `alias/microtodosuite-dev-vpc-flow-logs` | KMS | `alias/lex-mts-{shd-kms-tfstate,eco-kms-eks,eco-kms-flowlogs}` | New keys; old keys scheduled for deletion |
| `microtodosuite/{auth-api,frontend,log-message-processor,todos-api,users-api}` | ECR, 18 images | `lex-mts-shd-ecr-{authapi,frontend,logmsgproc,todosapi,usersapi}` | New repositories; images copied by digest |
| `microtodosuite/dev/*` (5) | ECR, empty | — | Delete (orphans) |
| `microtodosuite/{dev,staging,prod,demo}/auth-api-secrets` | Secrets | `lex-mts-eco-sm-jwt{dev,stg,prd,dmo}` | New secrets; values regenerated or copied |
| `microtodosuite/observability/alertmanager-slack-webhook`, `…/security/falcosidekick-slack-webhook` | Secrets holding human-supplied values | `lex-mts-eco-sm-slackobs`, `-slacksec` | **Values copied** before deletion |
| `microtodosuite.abrdns.com` | Route 53 zone | domain | **Keep**; import into `shd/dns`, retag |
| 4 observability PVC volumes (Prometheus 10 GiB, Loki 10 GiB, Jaeger 5 GiB, Grafana 2 GiB) | EBS | recreated by the cluster | **Snapshot**, then delete |
| `/aws/eks/microtodosuite-dev/cluster`, `/aws/vpc-flow-logs/microtodosuite-dev` | Log groups | follow the new names | Export, then delete |
| `esteban-developer`, `juan-developer`, `santiago-admin` | Human IAM users | — | Out of scope; `santiago-admin` is flagged for review |

No load balancer, ACM certificate, SQS queue, SSM parameter, or transit gateway
exists. The full-profile roots have never been applied.

## Target layout

```
aws/
  modules/                      decomposed under PC-IAC-023; local until extraction
    network/  eks-cluster/  eks-node-group/  iam-role/  kms-key/
    ecr-repository/  secret/  state-backend/  transit-egress/
  environments/
    shd/{state,security,registry,dns}/
    eco/{networking,security,workload,security-irsa}/
    fdev/  fstg/  fprd/         same domains; code only
config/aws-account.env          the one account declaration
```

State keys: `<environment>/<domain>/terraform.tfstate` in the new bucket.

## Order

**Preserve** (nothing destroyed yet): archive every state object and every local
backup; copy both Slack webhook values into their new secrets; snapshot the four
observability volumes; export the two log groups; export the Route 53 records;
copy every image, signature, and attestation to the new repositories and verify
each digest with Cosign; record the live GitOps revision.

**Build** (still nothing destroyed): write the modules and roots; plan each new
root against its empty key; update GitOps values from the planned outputs on a
branch; update the five service workflows, the reusable workflow's guard, and the
Kyverno repository pattern to the new repository and role names.

**Window** (the only downtime): pause ArgoCD auto-sync and CI publication; delete
workloads and their volumes through GitOps; destroy `eco` from a saved plan; apply
the new roots in order — `shd/state`, `shd/security`, `shd/registry`, `shd/dns`,
`eco/networking`, `eco/security`, `eco/workload`, `eco/security-irsa`; merge the
GitOps branch; run the audited bootstrap; resume sync and publication.

**Validate and clean**: the US3 checks; the orphan sweep of US4; delete the old
bucket, repositories, secrets, and keys after the retention the maintainer sets;
delete the default VPC.
