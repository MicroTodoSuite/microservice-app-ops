# fstg/workload

The full-staging environment's workload, third in the PC-IAC-022 order (ops
spec 004 T011, ai-agents specs/001 T025). It creates the cluster and its
bootstrap capacity.

| Resource | Module | Name |
| --- | --- | --- |
| EKS cluster, Kubernetes `kubernetes_version`, private API plus an optional public endpoint | `eks-cluster-v1.1.0` | `lex-mts-fstg-eks-main` |
| Control-plane log group, encrypted with fstg/security's logs key | `eks-cluster-v1.1.0` | `/aws/eks/lex-mts-fstg-eks-main/cluster`, `Name` tag `lex-mts-fstg-cwl-eks` |
| Access entries with `AmazonEKSClusterAdminPolicy` for `cluster_admin_principal_arns` | `eks-cluster-v1.1.0` | — |
| Managed add-ons: `eks-pod-identity-agent`, `vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver` | `eks-cluster-v1.1.0` | add-on names |
| Bootstrap managed node group and its launch template | `eks-node-group-v1.0.0` | `lex-mts-fstg-ng-bootstrap`, `lex-mts-fstg-lt-bootstrap` |
| Karpenter interruption queue, SQS-managed encryption, 300-second retention | `karpenter-interruption-v1.0.0` | `lex-mts-fstg-sqs-karpenter` |
| The five EventBridge rules that feed it | `karpenter-interruption-v1.0.0` | `lex-mts-fstg-evr-karpsched`, `-karpspot`, `-karprebal`, `-karpstate`, `-karpcapres` |

**What it reads.** It creates no IAM, KMS, or network resource. It reads what
`fstg/networking` and `fstg/security` created, by their standard names:
- the VPC;
- the private subnets, by the cluster's discovery tags;
- the cluster and node roles;
- the add-on roles;
- both keys;
- both security groups.

## Add-ons and their roles

- **Install order.** The Pod Identity agent, the CNI, and kube-proxy install
  with the cluster. CoreDNS and the EBS CSI driver wait for the bootstrap node
  group.
- **Roles through Pod Identity.** The CNI and the EBS CSI controller take
  fstg/security's roles through EKS Pod Identity, not IRSA. That role exists
  before the cluster, so the CNI is authorized on the first node without
  waiting for the cluster's OIDC provider.
- **CNI settings kept from the legacy cluster:**
  - network policy enforcement (`enableNetworkPolicy`), which ops spec 005's
    namespace isolation relies on;
  - prefix delegation (`ENABLE_PREFIX_DELEGATION`), for pod density on two
    nodes.
- **Pinned versions.** The legacy dev cluster's versions are in
  `fstg.tfvars.example`. `eks-pod-identity-agent` is new to this layout. Fill
  its version from:
  ```bash
  aws eks describe-addon-versions --addon-name eks-pod-identity-agent --kubernetes-version 1.35
  ```
  The plan refuses anything that is not a pinned `vX.Y.Z-eksbuild.N`.

## Nodes

The bootstrap group keeps the legacy capacity:
- two to four on-demand `m7i-flex.large` nodes;
- Amazon Linux 2023 at an explicit AMI release;
- 50 GiB encrypted gp3 root volumes;
- IMDSv2 with a hop limit of 1.

**Security groups.** The nodes carry two groups:
- the cluster security group Amazon EKS creates, for control-plane traffic,
  because a launch template that sets security groups stops EKS from adding
  it;
- `lex-mts-fstg-sg-node`, for node-to-node traffic and egress.

**Access entry.** Amazon EKS creates the node role's access entry itself, so
`cluster_admin_principal_arns` names only administrators.

## Karpenter prerequisites

Terraform owns the AWS side of Karpenter; GitOps owns the controller, its
NodePools, and its EC2NodeClasses (constitution principle 11, gitops spec 009
T086). This root creates what the controller needs to exist before it runs:

- **The interruption queue** `lex-mts-fstg-sqs-karpenter`. Its policy admits
  only `events.amazonaws.com` and `sqs.amazonaws.com` and denies every request
  made without TLS. It takes SQS-managed encryption rather than a customer key:
  the queue carries interruption notices, not secrets, and a key of its own in
  each of three environments would cost more than it protects.
- **A 300-second retention**, as Karpenter's reference template sets. An
  interruption notice is worthless once the instance is gone.
- **Five EventBridge rules**, one per event Karpenter acts on: an AWS Health
  scheduled change, a Spot interruption warning, a rebalance recommendation, an
  instance state change, and a capacity reservation interruption.

**What it does not create.** No node role of its own: the nodes Karpenter
launches take `lex-mts-fstg-role-node`, the bootstrap group's role, which Amazon
EKS already authorized on the cluster through the access entry it created for
that group. A second role would need a second access entry and a second
`iam:PassRole` grant for nothing. No controller identity either: that is an
IRSA role, and it belongs to `fstg/security-irsa`.

**What GitOps substitutes.** `karpenter_interruption_queue_name` into the
controller's interruption-queue setting, `karpenter_node_role_name` into the
EC2NodeClass `role`, and `cluster_name` into the `karpenter.sh/discovery`
selectors that find the private subnets fstg/networking tagged and the node
security group fstg/security tagged.

## API access

- **Private by default.** The API is private while `endpoint_public_access_cidrs` is
  empty.
- **Public, for named operators only.** Naming operator addresses opens the
  public endpoint to exactly those blocks. Real addresses go only in the
  gitignored `fstg.tfvars`, and `/0` is refused.
- **What this replaces.** The legacy dev root's `0.0.0.0/0` endpoint is the
  recorded Trivy AWS-0040 exception, which expires when this layout replaces
  it. Nothing here needs that exception.

## Deletion protection

`cluster_deletion_protection` defaults to `true`, so Amazon EKS refuses to
delete the cluster. The lifecycle's full-staging down transition turns it off in
a bundle of its own, then destroys the cluster from a second bundle. The next
plan of this root restores the default. See `docs/aws-profile-lifecycle.md`.

## Plan and apply

```bash
cp fstg.tfvars.example fstg.tfvars                             # fill the account, addresses, and agent version
cp workload.s3.tfbackend.example workload.s3.tfbackend       # fill from shd/state's outputs
terraform -chdir=aws/environments/fstg/workload init -backend-config=workload.s3.tfbackend
terraform -chdir=aws/environments/fstg/workload plan -input=false -var-file=fstg.tfvars -out=fstg-workload.tfplan
```

An apply uses only that saved plan, after the maintainer approves it
(MTS-IAC-107). It runs after `fstg/networking` and `fstg/security`. The state
key is new, so the apply records a `no-prior-state` receipt.

## Outputs

- `cluster_name`, `cluster_arn`, `cluster_endpoint`, `cluster_version`
- `cluster_certificate_authority_data`
- `cluster_oidc_issuer_url`, for the IRSA pass
- `cluster_security_group_id`
- `node_group_arn`
- `karpenter_interruption_queue_name`, `karpenter_interruption_queue_arn`
- `karpenter_node_role_name`
