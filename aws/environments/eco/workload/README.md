# eco/workload

The economical environment's workload, third in the PC-IAC-022 order (ops
spec 004 T011, ai-agents specs/001 T025). It creates the cluster and its
bootstrap capacity.

| Resource | Module | Name |
| --- | --- | --- |
| EKS cluster, Kubernetes `kubernetes_version`, private API plus an optional public endpoint | `eks-cluster-v1.1.0` | `lex-mts-eco-eks-main` |
| Control-plane log group, encrypted with eco/security's logs key | `eks-cluster-v1.1.0` | `/aws/eks/lex-mts-eco-eks-main/cluster`, `Name` tag `lex-mts-eco-cwl-eks` |
| Access entries with `AmazonEKSClusterAdminPolicy` for `cluster_admin_principal_arns` | `eks-cluster-v1.1.0` | — |
| Managed add-ons: `eks-pod-identity-agent`, `vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver` | `eks-cluster-v1.1.0` | add-on names |
| Bootstrap managed node group and its launch template | `eks-node-group-v1.0.0` | `lex-mts-eco-ng-bootstrap`, `lex-mts-eco-lt-bootstrap` |

**What it reads.** It creates no IAM, KMS, or network resource. It reads what
`eco/networking` and `eco/security` created, by their standard names:
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
  eco/security's roles through EKS Pod Identity, not IRSA. That role exists
  before the cluster, so the CNI is authorized on the first node without
  waiting for the cluster's OIDC provider.
- **CNI settings kept from the legacy cluster:**
  - network policy enforcement (`enableNetworkPolicy`), which ops spec 005's
    namespace isolation relies on;
  - prefix delegation (`ENABLE_PREFIX_DELEGATION`), for pod density on two
    nodes.
- **Pinned versions.** The legacy dev cluster's versions are in
  `eco.tfvars.example`. `eks-pod-identity-agent` is new to this layout. Fill
  its version from:
  ```bash
  aws eks describe-addon-versions --addon-name eks-pod-identity-agent --kubernetes-version 1.35
  ```
  The plan refuses anything that is not a pinned `vX.Y.Z-eksbuild.N`.

## Public entry point

The economical environments are published under the canonical zone
`microtodosuite.online`, which `shd/dns` creates:

| Environment | Host |
| --- | --- |
| prod | `eco.microtodosuite.online` |
| dev, staging, demo | `<env>.eco.microtodosuite.online` |

This root owns the AWS side of that entry point:
- **The certificate.** One ACM certificate, `lex-mts-eco-acm-ingress`, for
  `ingress_host` and `*.ingress_host`, DNS-validated through a single record in
  the canonical zone. The host and its wildcard share that record.
- **The address records.** A aliases for the host and its wildcard, pointing at
  the shared load balancer `lex-mts-eco-alb-main`.

GitOps owns everything else: the AWS Load Balancer Controller, the IngressClass,
and each environment's Ingress to its frontend. The controller creates the
load balancer from the Ingresses and discovers the certificate by host, so no
certificate ARN appears in Git.

**Everything waits for the delegation.** `public_zone_delegation_verified`
defaults to `false`, and until an operator sets it the root requests no
certificate and publishes no record (gitops spec 009 FR-044). Set it only
after the registrar's name servers for `public_zone_name` match `shd/dns`'s
`canonical_zone_name_server_names`.

**The records wait for the load balancer.** They are published only once the
controller has created the load balancer with the tags `elbv2.k8s.aws/cluster`
and `ingress.k8s.aws/stack`. A first bring-up therefore plans no record. After
GitOps reconciles the Ingresses, run the next plan of this root to add them. A
`down` destroys the certificate and the records with the cluster, after
GitOps quiescence has removed the load balancer.



The bootstrap group runs:
- three on-demand `m7i-flex.large` nodes, able to grow to four, as capacity
  limit L3 sets since its 2026-09-14 amendment;
- Amazon Linux 2023 at an explicit AMI release;
- 50 GiB encrypted gp3 root volumes;
- IMDSv2 with a hop limit of 1.

**Security groups.** The nodes carry two groups:
- the cluster security group Amazon EKS creates, for control-plane traffic,
  because a launch template that sets security groups stops EKS from adding
  it;
- `lex-mts-eco-sg-node`, for node-to-node traffic and egress.

**Access entry.** Amazon EKS creates the node role's access entry itself, so
`cluster_admin_principal_arns` names only administrators.

## API access

- **Private by default.** The API is private while `endpoint_public_access_cidrs` is
  empty.
- **Public, for named operators only.** Naming operator addresses opens the
  public endpoint to exactly those blocks. Real addresses go only in the
  gitignored `eco.tfvars`, and `/0` is refused.
- **What this replaces.** The legacy dev root's `0.0.0.0/0` endpoint is the
  recorded Trivy AWS-0040 exception, which expires when this layout replaces
  it. Nothing here needs that exception.

## Deletion protection

`cluster_deletion_protection` defaults to `true`, so Amazon EKS refuses to
delete the cluster. The lifecycle's economical down transition turns it off in
a bundle of its own, then destroys the cluster from a second bundle. The next
plan of this root restores the default. See `docs/aws-profile-lifecycle.md`.

## Plan and apply

```bash
cp eco.tfvars.example eco.tfvars                             # fill the account, addresses, and agent version
cp workload.s3.tfbackend.example workload.s3.tfbackend       # fill from shd/state's outputs
terraform -chdir=aws/environments/eco/workload init -backend-config=workload.s3.tfbackend
terraform -chdir=aws/environments/eco/workload plan -input=false -var-file=eco.tfvars -out=eco-workload.tfplan
```

An apply uses only that saved plan, after the maintainer approves it
(MTS-IAC-107). It runs after `eco/networking` and `eco/security`. The state
key is new, so the apply records a `no-prior-state` receipt.

## Outputs

- `cluster_name`, `cluster_arn`, `cluster_endpoint`, `cluster_version`
- `cluster_certificate_authority_data`
- `cluster_oidc_issuer_url`, for the IRSA pass
- `cluster_security_group_id`
- `node_group_arn`
