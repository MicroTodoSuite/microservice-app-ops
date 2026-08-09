# Data Model: AWS Dev Foundation

This feature is infrastructure as code rather than an application database.
The model therefore describes configuration records, managed resource groups,
contracts, and their invariants.

## Relationships

```text
DevFoundationConfiguration
├── DevNetwork
├── EksCluster
│   ├── ManagedBootstrapNodeGroup
│   ├── EksAccessEntries
│   └── WorkloadIdentityBindings
├── ImageRepositorySet
└── GitOpsRegistrationHandoff

RemoteStateConfiguration
├── StateBucket
├── StateKmsKey
└── FoundationStateAddress
```

The backend bootstrap root owns `RemoteStateConfiguration`. The foundation root
uses that state address and owns everything under
`DevFoundationConfiguration`; neither state imports existing Azure resources.

## DevFoundationConfiguration

| Field | Type | Required rule |
| --- | --- | --- |
| `environment` | string | Constant `dev`; no arbitrary environment input in this root. |
| `project` | string | Canonical `microtodosuite`, used for names and tags. |
| `expected_account_id` | 12-digit string | Must match the caller account before planning resources. |
| `aws_region` | string | Human-approved `us-east-1`. |
| `availability_zones` | list(string) | Exactly `us-east-1a`, `us-east-1b`, and `us-east-1c`. |
| `vpc_cidr` | IPv4 CIDR | Dev-reserved `10.10.0.0/16`; must contain all dev subnets. |
| `public_subnet_cidrs` | list(IPv4 CIDR) | Three distinct, non-overlapping CIDRs, one per AZ. |
| `private_subnet_cidrs` | list(IPv4 CIDR) | Three distinct, non-overlapping CIDRs, one per AZ and not overlapping public subnets. |
| `cluster_public_access_cidrs` | list(IPv4 CIDR) | Exactly `0.0.0.0/0` for dev by explicit human approval; future environments require restricted CIDRs. |
| `bootstrap_admin_principal_arns` | set(IAM ARN) | Approved short-lived human/automation roles; no IAM users. |
| `node_instance_types` | list(string) | Approved On-Demand x86 types with at least 2 vCPU/8 GiB; example defaults to `m6i.large`. |
| `common_tags` | map(string) | Must not override required project/environment/owner/managed-by tags. |

### Required metadata

Every taggable resource carries at least:

```text
Project     = MicroTodoSuite
Environment = dev
ManagedBy   = Terraform
Owner       = Platform
```

## DevNetwork

| Attribute | Invariant |
| --- | --- |
| VPC | One VPC owned only by dev. |
| AZ topology | Three public/private subnet pairs across three AZs. |
| Worker reachability | Private subnets do not assign public IPv4 addresses. |
| Egress | One NAT gateway per AZ; each private route uses its zonal NAT. |
| Load balancer discovery | Public subnets have `kubernetes.io/role/elb=1`; private subnets have `kubernetes.io/role/internal-elb=1`. |
| Karpenter discovery | Only private workload subnets have `karpenter.sh/discovery=<cluster-name>`. |
| Audit | VPC flow logs are enabled with encrypted retention-owned storage. |

## EksCluster

| Attribute | Value or invariant |
| --- | --- |
| Environment | `dev` |
| Kubernetes version | Exactly `1.35` |
| API endpoint | Private enabled; public enabled only for the explicit CIDR allowlist. |
| Authentication | EKS API access entries; no new `aws-auth` mappings. |
| Control-plane logs | API, audit, authenticator, controller manager, and scheduler enabled. |
| Managed add-ons | VPC CNI, CoreDNS, and kube-proxy with compatible AWS-selected versions. |
| Secrets encryption | Uses an environment-owned KMS key or EKS-supported envelope-encryption configuration. |
| Node placement | Private subnets only. |

### ManagedBootstrapNodeGroup

| Attribute | Value or invariant |
| --- | --- |
| Capacity type | `ON_DEMAND` |
| AMI family | AL2023 x86-64 |
| Size | minimum 2, desired 2, maximum 4 |
| Placement | All three private workload subnets |
| Storage | Encrypted gp3 root volumes |
| Access | No SSH key; IMDSv2 required with hop limit 1 |
| Operations | Node repair enabled; remains available after later Karpenter adoption |

## WorkloadIdentityBinding

| Field | Type | Validation |
| --- | --- | --- |
| `namespace` | Kubernetes DNS label | Exact, non-empty; no wildcard. |
| `service_account` | Kubernetes DNS label | Exact, non-empty; no wildcard. |
| `subject` | derived string | `system:serviceaccount:<namespace>:<service_account>`. |
| `audience` | string | Exactly `sts.amazonaws.com`. |
| `role_arn` | IAM role ARN | One role per approved binding. |
| `policy_arns` | set(IAM policy ARN) | Explicit approved policies only. |

The first concrete binding is `kube-system/aws-node` to a dedicated VPC CNI
role. `AmazonEKS_CNI_Policy` is absent from the worker-node role. Future
application/add-on bindings must be added as reviewed records; the empty future
set does not create a wildcard placeholder.

## ImageRepositorySet

The set is fixed for this feature:

```text
auth-api
todos-api
users-api
frontend
log-message-processor
```

Each repository is named `microtodosuite/dev/<service>` and has these
invariants:

- Tag mutability is `IMMUTABLE`, with no exclusions.
- Encryption is AES-256 at rest.
- Basic scan-on-push is enabled at repository scope.
- `force_delete` is false.
- Lifecycle deletion addresses only untagged images older than 30 days.
- The output is a repository URL, never a mutable deployment tag.

## RemoteStateConfiguration

| Field | Type | Required rule |
| --- | --- | --- |
| `environment` | string | Constant `dev`. |
| `expected_account_id` | 12-digit string | Same account guard as the foundation. |
| `aws_region` | string | Same region used by backend configuration. |
| `operator_principal_arns` | set(IAM ARN) | Explicit approved roles only. |
| `bucket_name` | derived string | Includes project, account, region, and dev; globally unique. |
| `foundation_key` | string | `environments/dev/foundation/terraform.tfstate`. |
| `bootstrap_key` | string | `environments/dev/backend-bootstrap/terraform.tfstate`. |
| `lock_key` | derived string | `<foundation_key>.tflock`. |
| `kms_key_arn` | output | Dev backend CMK with rotation enabled. |

The bucket enables versioning, bucket-owner enforcement, TLS-only access,
public-access blocking, and deletion protection. State permissions and lock
permissions are distinct; no workload role is an authorized principal.

## GitOpsRegistrationHandoff

| Field | Source | Consumer |
| --- | --- | --- |
| `environment` | constant `dev` | Activation `env`; namespace derivation. |
| `namespace` | derived `microtodo-dev` | Validation/reference only; current templates derive it. |
| `activation_server` | constant `https://kubernetes.default.svc` | Both current activation lists under per-cluster ArgoCD. |
| `cluster_name`, `cluster_arn` | EKS | Bootstrap and operator inventory. |
| `cluster_endpoint`, `cluster_certificate_authority_data` | EKS | Kubeconfig and audited one-time ArgoCD bootstrap, not activation. |
| `aws_region` | configuration | AWS-specific registration/environment resources. |
| `ecr_repository_urls` | ECR map | Service overlay `images[].newName`; GitOps supplies digest. |
| `oidc_issuer_url`, `oidc_provider_arn` | EKS/IAM | Later exact IRSA bindings. |
| `private_subnet_ids`, `karpenter_security_group_id` | VPC/EKS | Later Terraform-owned Karpenter IAM/capacity spec. |
| `irsa_role_arns` | IAM map | Registration/environment service-account annotations. |

`repoURL`, `revision`, and OCI image digests are intentionally absent because
they are reviewed Git values.

## Lifecycle States

### Remote backend

```text
ABSENT -> LOCALLY_BOOTSTRAPPED -> REMOTE_MIGRATION_REVIEWED -> REMOTE_ACTIVE
                                                       |
                                                       +-> VERSION_RECOVERY
```

- `ABSENT`: no backend bucket; foundation init must fail clearly.
- `LOCALLY_BOOTSTRAPPED`: backend plan/state is local and separately guarded.
- `REMOTE_MIGRATION_REVIEWED`: bucket/KMS outputs have been placed in reviewed
  partial backend configuration; state migration is an explicit operator step.
- `REMOTE_ACTIVE`: foundation state is encrypted, versioned, and natively
  locked; normal teammate planning is permitted.
- `VERSION_RECOVERY`: an incident-controlled prior S3 version is restored,
  followed by a fresh plan before any mutation.

### Foundation

```text
UNCONFIGURED -> INITIALIZED -> VALIDATED -> PLANNED -> PROVISIONED -> CONVERGED
```

This feature's specification workflow stops at executable implementation tasks.
Its operator preview contract stops at `PLANNED`; provisioning is never invoked
implicitly by the wrapper.
