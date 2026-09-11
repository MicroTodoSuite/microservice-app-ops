# Implementation Plan: Naming-Convention Adoption and Infrastructure Rebuild

## Inventory — deployed on 2026-09-11 (read-only API calls)

| Current | Kind | New name | Treatment |
| --- | --- | --- | --- |
| `microtodosuite-dev` | EKS cluster, Kubernetes 1.35 | `gcs-mts-eco-eks-main` | Recreate |
| `bootstrap-35e466b0…` | Node group, 2 × `m7i-flex.large` | `gcs-mts-eco-ng-bootstrap` | Recreate |
| `aws-ebs-csi-driver`, `coredns`, `kube-proxy`, `vpc-cni` | EKS add-ons | same add-on names | Recreate with the cluster |
| `microtodosuite-dev` | VPC `10.10.0.0/16` | `gcs-mts-eco-vpc-main` | Recreate |
| 6 subnets, 5 route tables, 1 IGW, 3 NAT, 3 EIP, NACL, flow log | Network | `gcs-mts-eco-{sub,rtb,igw,nat,eip,fl}-…` | Recreate |
| default VPC `172.31.0.0/16` | Network, not Terraform | — | Delete (capacity limit L1) |
| 5 security groups | Security | `gcs-mts-eco-sg-cluster`, `-node`; EKS-created group unchanged | Recreate |
| `microtodosuite-dev-node`, `-dev-cluster-…`, `-dev-ebs-csi`, `-dev-vpc-cni` | IAM roles | `gcs-mts-eco-role-{node,cluster,ebscsi,vpccni}` | Recreate |
| `microtodosuite-{dev,staging,prod,demo}-jwt-reader` | IRSA roles | `gcs-mts-eco-role-jwt{dev,stg,prd,dmo}` | Recreate |
| `microtodosuite-observability-secrets-reader`, `-security-secrets-reader` | IRSA roles | `gcs-mts-eco-role-obssecret`, `-secsecret` | Recreate |
| `microtodosuite-github-ecr-publisher` | IAM role | `gcs-mts-shd-role-ecrpublish` | Recreate |
| `microtodosuite-kyverno-ecr-verifier` | IAM role | `gcs-mts-shd-role-kyvernoecr` | Recreate |
| `microtodosuite-terraform-dev` | Deploy role | `gcs-mts-shd-role-tfdeploy` | Create first, retire last |
| 2 customer policies | IAM | `gcs-mts-eco-pol-…` | Recreate |
| EKS OIDC provider | IAM | issuer URL | Recreate with the cluster |
| GitHub OIDC provider | IAM | issuer URL | **Keep**; import into `shd/security` |
| `microtodosuite-tfstate-575172595729-us-east-1-dev` | S3 state bucket | `gcs-mts-shd-s3-tfstate-575172595729` | New bucket; old one archived, then deleted |
| `alias/microtodosuite-tfstate-…`, `alias/eks/microtodosuite-dev`, `alias/microtodosuite-dev-vpc-flow-logs` | KMS | `alias/gcs-mts-{shd-kms-tfstate,eco-kms-eks,eco-kms-flowlogs}` | New keys; old keys scheduled for deletion |
| `microtodosuite/{auth-api,frontend,log-message-processor,todos-api,users-api}` | ECR, 18 images | `gcs-mts-shd-ecr-{authapi,frontend,logmsgproc,todosapi,usersapi}` | New repositories; images copied by digest |
| `microtodosuite/dev/*` (5) | ECR, empty | — | Delete (orphans) |
| `microtodosuite/{dev,staging,prod,demo}/auth-api-secrets` | Secrets | `gcs-mts-eco-sm-jwt{dev,stg,prd,dmo}` | New secrets; values regenerated or copied |
| `microtodosuite/observability/alertmanager-slack-webhook`, `…/security/falcosidekick-slack-webhook` | Secrets holding human-supplied values | `gcs-mts-eco-sm-slackobs`, `-slacksec` | **Values copied** before deletion |
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
