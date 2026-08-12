# Contract: Terraform Dev Preview

## Supported entry point

Teammates invoke `scripts/aws-dev-foundation.sh` from the repository root. The
script resolves all internal paths itself and supports only these subcommands:

| Subcommand | Required behavior | Cloud mutation |
| --- | --- | --- |
| `check` | Verify pinned tool versions, authentication presence, expected local config files, formatting, shell contract, and prohibited secret patterns. | None |
| `init` | Initialize the dev foundation root with its explicit partial backend configuration and read-only dependency lock selection. | Backend metadata and provider/module downloads only; no infrastructure resources |
| `validate` | Run Terraform configuration validation for the dev foundation root. | None |
| `test` | Run mocked Terraform tests and repository contract tests. | None |
| `plan` | Generate an interactive-review plan with `-input=false`, explicit dev variables, and a bounded lock timeout. Do not save a plan artifact by default. | Read-only infrastructure refresh and temporary state lock only |
| `cost` | Run Infracost against the same dev root and inputs. | Read-only pricing lookup only |

There is no `apply`, `destroy`, GitOps-write, cluster-registration, or `kubectl`
subcommand.

## Configuration inputs

The wrapper requires:

- `aws/environments/dev/foundation/dev.s3.tfbackend`, created locally from the
  committed example and ignored by Git.
- Committed, human-approved `dev.tfvars` files in both dev Terraform roots;
  they contain non-secret environment configuration and no credentials.
- Terraform `1.15.8` and a dependency lock file committed for the root.
- AWS CLI v2 using an approved short-lived/federated role in the expected
  account.
- Three explicit `us-east-1` AZs and the accepted dev-only `0.0.0.0/0` EKS API
  policy, with authorization enforced through IAM and exact EKS access entries.

The wrapper must not accept access keys as command arguments, echo credentials,
infer an account from a bucket name, or silently select a different environment.

## Four-command normal flow

After prerequisites and local configuration are present, the supported plan
flow is exactly:

```bash
./scripts/aws-dev-foundation.sh check
./scripts/aws-dev-foundation.sh init
./scripts/aws-dev-foundation.sh validate
./scripts/aws-dev-foundation.sh plan
```

Any failure is non-zero and stops the sequence. The output identifies which
prerequisite/configuration is missing without printing sensitive values.

## Plan inventory contract

A valid first plan contains exactly the dev scope represented by the design:

- One dedicated three-AZ VPC, three public subnets, three private worker
  subnets, zonal NAT egress, routes, required discovery tags, and flow logging.
- One EKS 1.35 cluster with bounded API access, control-plane logging, API access
  entries, managed system add-ons, and the bootstrap node group. The VPC CNI
  add-on configuration explicitly sets `enableNetworkPolicy = "true"` so its
  node agent can enforce GitOps-owned policy objects.
- Exactly five named immutable, encrypted, scan-on-push ECR repositories and
  untagged-only lifecycle rules.
- EKS OIDC provider, exact VPC CNI IRSA role, limited node role, and required
  encryption/logging IAM/KMS resources.
- Structured GitOps handoff outputs.

It contains no staging, production, economical single-cluster, AKS, Route 53
failover, ECR-to-ACR replication, DynamoDB lock, Karpenter controller/capacity,
ArgoCD, Kubernetes object, or existing Azure resource changes.

## Repeatability contract

- A second plan after authorized provisioning, with unchanged inputs and state,
  reports no changes.
- A plan fails before resource evaluation if the caller account differs from
  `expected_account_id`.
- Missing backend, wrong KMS key, inaccessible lock, unsupported EKS region/AZ,
  overlapping CIDRs, empty operator principals, or an unreviewed change to the
  exact dev API CIDR fail with actionable validation errors.
- An existing but unmanaged ECR repository causes an explicit import-or-rename
  decision; the wrapper never auto-imports it.

## CI contract

`.github/workflows/aws-dev-foundation-checks.yml` is pull-request safe and does
not plan against live AWS. It pins the declared Terraform version and runs:

1. Terraform formatting.
2. Backend-free init and validation for both new roots.
3. Mocked Terraform tests.
4. ShellCheck and `tests/contract/aws-dev-foundation.sh`.
5. Trivy configuration scanning.
6. Infracost configuration validation when its token is available through the
   approved repository mechanism.

CI never receives committed AWS keys and never applies infrastructure.

## Exit and artifact behavior

- Exit `0`: requested check completed successfully.
- Non-zero: validation, initialization, lock, authentication, plan, test, or
  cost check failed; no later action is attempted.
- Saved binary plans, local backend config, unapproved variable files, state,
  and Terraform caches remain ignored; the two approved dev tfvars are tracked.
- Text/JSON plan output must be treated as potentially sensitive and is not
  uploaded by default.
