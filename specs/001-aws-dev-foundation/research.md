# Phase 0 Research: AWS Dev Foundation

## Decision 1: Use the ratified full profile

**Decision**: Create one VPC and one EKS cluster dedicated to `dev` in the
single AWS account.

**Rationale**: The constitution makes dedicated clusters/VPCs the default.
Namespace-only separation belongs to the economical profile and requires a
formal amendment. This matches the full Eraser diagram's dev isolation and
intentionally does not adopt the optimized diagram's single-cluster layout.

**Alternatives rejected**: A shared EKS cluster with dev/staging/prod namespaces;
separate AWS accounts; adding future environment resources now.

## Decision 2: Pin the toolchain and Kubernetes minor

**Decision**: Pin Terraform `1.15.8`, AWS provider `6.58.0`, VPC module `6.6.1`,
EKS module `21.24.2`, and EKS Kubernetes minor `1.35`. AWS chooses and maintains
the EKS platform patch.

**Rationale**: Terraform 1.15.8 supports native S3 locking. EKS 1.35 is in
standard support and is the newest minor inside the locally validated KEDA
2.20.1/Kyverno 1.18 compatibility boundary. Version 1.36 is deliberately not
selected, so no newer-version risk exception is needed.

**Alternatives rejected**: Existing workflow pin `1.5.0`, because it predates
native S3 locking; unpinned `latest`; EKS 1.36, because it exceeds the confirmed
add-on range.

**Sources**: [Terraform installation](https://developer.hashicorp.com/terraform/install),
[AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs),
[VPC module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest),
[EKS module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest),
[EKS lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html),
[EKS platform versions](https://docs.aws.amazon.com/eks/latest/userguide/platform-versions.html).

**Implementation prerequisite discovered**: EKS module 21.24.2 resolves an
assumed caller's source role through `aws_iam_session_context` during
provisioning. The current preview profile can call STS but is denied
IAM read/list access on its own execution role and on Terraform-managed roles
and policies. A post-failure refresh specifically confirmed missing
`iam:GetRole`, `iam:GetPolicy`, `iam:ListRolePolicies`, and
`iam:ListAttachedRolePolicies`, followed by `iam:GetPolicyVersion` and
`iam:GetOpenIDConnectProvider` as the refresh progressed. The review plan
therefore orders the module behind the fixed input guard, but a separately
authorized account administrator must grant the provisioning identity the
read/list permissions required to refresh its managed IAM resources. This
implementation does not mutate that external operator role.

## Decision 3: Use a resilient three-AZ network

**Decision**: Deploy dev in `us-east-1` across `us-east-1a`, `us-east-1b`, and
`us-east-1c`. Create one public and one private workload subnet in each AZ.
Nodes have no public IPs; public subnets host one NAT gateway per AZ and approved
internet-facing load balancers. Tag subnets for public/internal load balancer
discovery and tag only private workload subnets for future Karpenter discovery.
Enable VPC flow logs.

Reserve `10.10.0.0/16` for dev. Later staging and production specs use
non-overlapping `10.20.0.0/16` and `10.30.0.0/16` ranges respectively.

Enable both private and public EKS API access. Dev intentionally configures
`0.0.0.0/0` because the small team's source IPs are dynamic; IAM authentication
and exact EKS access entries remain the authorization boundary. This is an
explicit human-approved dev tradeoff: it must not be silently narrowed, and
staging/production must use restricted network policies instead of copying it.

**Rationale**: Three AZs preserve the full-profile resilience visible in the
architecture and avoid cross-AZ NAT dependencies. Private workers prevent
direct node exposure, while IAM and EKS access entries keep API authorization
explicit despite the accepted dev-only network reachability tradeoff.

**Alternatives rejected**: Two AZs; one NAT gateway; public worker addresses;
silently substituting a transient individual `/32` for the approved dev policy;
copying the dev global CIDR into staging/production; dedicated control-plane
subnets at this scale.

**Sources**: [EKS subnet best practices](https://docs.aws.amazon.com/eks/latest/best-practices/subnets.html),
[EKS network requirements](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html),
[NAT gateway resilience](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html).

## Decision 4: Bootstrap with stable managed capacity

**Decision**: Create one On-Demand, AL2023 x86-64 managed node group across the
private subnets with `min=2`, `desired=2`, and `max=4`. The default instance is
`m7i-flex.large`, configurable only to approved types with at least 2 vCPU and
8 GiB. Use encrypted gp3 volumes, no SSH key, IMDSv2, node repair, and multi-AZ
placement. Enable EKS control-plane logs and managed CoreDNS, kube-proxy, and
VPC CNI add-ons. Use a module-generated `bootstrap-` physical-name prefix while
retaining the stable `Name=bootstrap` tag and capacity-owner label.

**Rationale**: The cluster needs capacity before ArgoCD or Karpenter exists. Two
On-Demand nodes keep controllers available during one-node/AZ disruption and
avoid making a cost-driven Spot choice silently. A live account query confirmed
that `m7i-flex.large` is Free Tier eligible, x86-64, current-generation,
On-Demand, 2 vCPU/8 GiB, and offered in all three selected AZs. The original
`m6i.large` choice failed at runtime because this account currently rejects EC2
types that are not Free Tier eligible. The pinned managed-node-group module
enforces create-before-destroy. A generated suffix therefore allows a healthy
replacement to be created alongside the old group; a fixed `bootstrap` name
caused EKS to reject the replacement with `ResourceInUseException`.

**Alternatives rejected**: Spot bootstrap nodes; Fargate; burstable small
instances; the Free Tier eligible `c7i-flex.large` and T-family types because
they do not meet the 8-GiB stable-capacity contract; Arm-based T4g types; keeping
`m6i.large` while the account rejects it; a fixed physical node-group name that
cannot satisfy create-before-destroy; relying on Karpenter or a cluster
autoscaler for initial capacity.

**Sources**: [EKS managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html),
[AL2023 EKS AMIs](https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html).

## Decision 5: Prove IRSA with exact trust

**Decision**: Create the EKS IAM OIDC provider with audience
`sts.amazonaws.com`. Create an exact IRSA role for
`system:serviceaccount:kube-system:aws-node`, attach
`AmazonEKS_CNI_Policy` to that role, and associate it with the VPC CNI add-on.
Keep the node role limited to worker-node and ECR pull permissions. Represent
future workload bindings as exact namespace/service-account records; create no
broad placeholder role. Use EKS access entries rather than new `aws-auth`
mappings for bootstrap/operator principals. Pin EKS secrets-key administrators
to the reviewed bootstrap role ARNs rather than allowing the module to derive a
different administrator from whichever caller happens to run Terraform.

**Rationale**: This exercises the complete OIDC-to-service-account path and
keeps network permissions off every pod on a node. No application AWS resource
contract is approved yet, so pre-creating a wildcard workload role would violate
least privilege.

**Current-practice deviation proposed for later review**: AWS now recommends
EKS Pod Identity whenever possible because it removes per-cluster OIDC-provider
trust updates, reduces direct workload STS use, and supports session tags. This
would conflict with the constitution and this specification's explicit IRSA
choice, so this implementation does not switch silently. A later amendment/spec
may evaluate Pod Identity for application workloads while preserving or
migrating the exact CNI binding deliberately.

**Alternatives rejected for this pass**: Node-role CNI permissions; wildcard
`sub` claims; static access keys; a broad future-workload role; silently
replacing the specified IRSA contract with EKS Pod Identity.

**Sources**: [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html),
[VPC CNI IRSA](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html),
[EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html),
[EKS Pod Identity and IRSA comparison](https://docs.aws.amazon.com/eks/latest/userguide/service-accounts.html).

## Decision 6: Create five digest-oriented ECR repositories

**Decision**: Create
`microtodosuite/dev/{auth-api,todos-api,users-api,frontend,log-message-processor}`
repositories with immutable tags and no exclusions, AES-256 encryption,
repository-scoped scan-on-push, `force_delete=false`, and deletion only of
untagged images older than 30 days. Output repository URLs by service.

**Rationale**: Tagged digests may still be referenced by GitOps, so automatic
tagged-image deletion is unsafe. Repository-scoped scanning avoids making one
environment own account/region-wide enhanced scanning configuration.

**Alternatives rejected**: Mutable tags or `latest`; tag exclusions; automatic
tagged-image count deletion; account-wide enhanced scanning in this spec; using
tag equality as cross-registry promotion proof.

**Sources**: [ECR tag immutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html),
[image scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning.html),
[encryption](https://docs.aws.amazon.com/AmazonECR/latest/userguide/encryption-at-rest.html),
[lifecycle policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html).

## Decision 7: Use a separate S3/KMS bootstrap root and native lockfile

**Decision**: A dedicated dev backend root creates a bucket named from project,
account, region, and environment plus a customer-managed rotating KMS key. It
enables versioning, bucket-owner enforcement, full public-access blocking,
TLS-only access, lifecycle protection, and `force_destroy=false`. Foundation
state uses key `environments/dev/foundation/terraform.tfstate` and the native
lock object `environments/dev/foundation/terraform.tfstate.tflock`.

The bootstrap root begins with local state and is migrated, as a separately
reviewed operator action, to
`environments/dev/backend-bootstrap/terraform.tfstate` after the bucket exists.
The committed partial backend example contains no credentials. Backend policy
grants state read/write and lock create/read/delete only to approved operator/CI
roles; workload roles receive no state access.

**Rationale**: A root cannot create the backend on which its own first plan
depends. Dedicated environment naming and native S3 conditional locking prevent
future state collisions without introducing the deprecated DynamoDB mechanism
shown in the diagrams.

**Alternatives rejected**: One state key for all environments; workspaces as the
isolation boundary; a new DynamoDB lock table; access keys in backend config;
auto-expiring noncurrent state versions; letting workloads read state.

**Sources**: [S3 backend and native locking](https://developer.hashicorp.com/terraform/language/backend/s3),
[partial backend configuration](https://developer.hashicorp.com/terraform/language/backend#partial-configuration),
[S3 versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html),
[S3 public-access blocking](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html),
[S3 SSE-KMS](https://docs.aws.amazon.com/AmazonS3/latest/userguide/UsingKMSEncryption.html).

## Decision 8: Expose one non-mutating operator entry point

**Decision**: `scripts/aws-dev-foundation.sh` is the supported interface with
`check`, `init`, `validate`, `test`, `plan`, and optional `cost` subcommands.
After local non-secret config and authenticated prerequisites exist, the normal
preview is four commands: `check`, `init`, `validate`, `plan`. Every Terraform
invocation uses `-chdir`; plan uses `-input=false`, a bounded lock timeout, and
no saved plan by default. The script has no `apply` subcommand.

**Rationale**: Teammates should not need to learn the module tree, while each
safe lifecycle step remains visible and diagnosable.

**Alternatives rejected**: Documenting internal `cd` sequences; a Make target
that hides backend selection; automatic backend creation; an apply-capable
wrapper; committed account credentials.

## Decision 9: Test structure and cost before cloud mutation

**Decision**: Commit provider lock files per root. CI runs formatting,
backend-free initialization/validation, mocked Terraform tests, shell and
contract checks, Trivy configuration scanning, and Infracost configuration
validation. Authenticated plan and cost review are operator/approved workflow
steps; CI does not receive static AWS credentials.

**Rationale**: Mock tests validate resource contracts without an account or
apply. Infracost keeps the three NAT gateways and worker capacity visible.

**Alternatives rejected**: Treating `terraform validate` alone as sufficient;
ignoring dependency lock files; silently reducing NAT/node capacity; an
apply-on-pull-request workflow.

**Sources**: [Terraform test](https://developer.hashicorp.com/terraform/cli/commands/test),
[mock providers](https://developer.hashicorp.com/terraform/language/tests/mocking),
[dependency lock files](https://developer.hashicorp.com/terraform/language/files/dependency-lock).

## Decision 10: Map outputs to the implemented per-cluster GitOps seam

**Decision**: Output a structured handoff with `env=dev`, derived
`namespace=microtodo-dev`, cluster name/ARN, raw endpoint and certificate
authority, activation `server=https://kubernetes.default.svc`, AWS region, ECR
URL map, OIDC issuer/provider ARN, private subnet IDs, selected node security
group ID, and created IRSA role ARNs. Do not output Git-owned `repoURL`,
`revision`, overlay digests, or mutate GitOps.

**Rationale**: The current `clusters/local-kind` registration stores only
`repoURL` and `revision`; activation lists carry `env` and `server`; namespace is
derived as `microtodo-{{ .env }}`. Current `infrastructure.yaml` and AppProject
destinations target the in-cluster API, so a per-cluster ArgoCD root is the only
implemented topology that needs no Terraform-output redesign.

**Current GitOps facts**:

- `clusters/local-kind/kustomization.yaml` owns the replacement wiring, so a
  sibling is not literally value-only until GitOps extracts or duplicates it.
- The future-EKS conformance script and fixtures referenced by spec 001 remain
  unfinished.
- The architecture decision is per-cluster ArgoCD with in-cluster
  destinations. `docs/profiles.md`, `clusters/README.md`, and the stale
  dual-topology comment in `clusters/base/apps.yaml` were corrected in this pass
  to match current manifests and the DR independence requirement.
- The platform-addons registration contract was corrected in this pass to name
  four controller add-ons plus Redis as the fifth infrastructure root, matching
  current discovery and contract tests.

**Alternatives rejected**: Feeding the raw EKS endpoint into current activation
patches; centralizing reconciliation in `eks-prod`; having Terraform write Git
values; assuming namespace is a registration input.

## Decision 11: Prepare only the stable Karpenter seam

**Decision**: Add `karpenter.sh/discovery=<cluster-name>` to private workload
subnets and exactly one selected node security group. Output those IDs and keep
the managed node group permanently usable for controllers.

**Rationale**: These discovery boundaries survive a later Karpenter version
choice. Controller, CRDs, NodePool/EC2NodeClass, and Kubernetes resources are
ArgoCD-owned; IAM, interruption queue, and EventBridge resources are
Terraform-owned but need a later coordinated spec.

**Alternatives rejected**: Installing Karpenter now; creating unused IAM/SQS
privilege now; making bootstrap capacity depend on Karpenter.

**Sources**: [Karpenter NodeClass discovery](https://karpenter.sh/docs/concepts/nodeclasses/),
[Karpenter compatibility](https://karpenter.sh/preview/upgrading/compatibility/).

## Decision 12: Preserve legacy Azure roots unchanged

**Decision**: Add AWS files only under `aws/` plus isolated scripts, tests,
documentation, and checks. Do not refactor or import the existing Azure backend,
base-infrastructure, container-app roots, workflows, or stale destroy workflow
as part of this feature.

**Rationale**: Those are independent deployed roots with their own state and
unrelated user-owned migration debt. Mixing providers or state would make the
dev plan unsafe and violate the requested scope.

**Alternatives rejected**: Converting existing roots in place; reusing Azure
state naming; fixing unrelated Azure workflow debt during AWS foundation work.

## Decision 13: Make VPC CNI network-policy enforcement Terraform-owned

**Decision**: Configure the pinned `vpc-cni` managed add-on with
`configuration_values = jsonencode({ enableNetworkPolicy = "true" })`. Retain
the add-on's standard enforcement mode and default node-agent ports; GitOps
continues to own all Kubernetes `NetworkPolicy` manifests.

**Rationale**: The installed `v1.23.0-eksbuild.1` add-on schema exposes
`enableNetworkPolicy` as a string-formatted boolean, and AWS documents the
literal string `"true"` for managed add-ons. The live DaemonSet already includes
the `aws-eks-nodeagent` container, but its current argument is
`--enable-network-policy=false`; declarative add-on configuration removes that
drift and makes the existing namespace policies enforceable after an authorized
apply.

**Alternatives rejected**: Editing the DaemonSet directly; setting the flag with
an imperative AWS CLI command; moving `NetworkPolicy` manifests into Terraform;
silently opting into strict startup enforcement; overriding node-agent ports
without a demonstrated conflict.

**Sources**: [Configure VPC CNI network policies](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html),
[VPC CNI network-policy requirements](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html).
