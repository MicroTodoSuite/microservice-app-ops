# Quickstart: Preview the AWS Dev Foundation

This is the target operator workflow for the implementation tasks in this
feature. The wrapper and Terraform roots do not exist until those tasks are
implemented. This quickstart intentionally contains no apply or direct cluster
mutation command.

## 1. Prerequisites

Before the four-command flow, an approved platform operator provides:

- Terraform `1.15.8`.
- AWS CLI v2 authenticated with a short-lived or federated role in the expected
  AWS account.
- ShellCheck, Trivy, and Infracost for the complete local review path.
- An already provisioned and migrated dev state backend that satisfies
  [the remote-state contract](./contracts/remote-state.md).
- The committed, human-approved dev values in each root's `dev.tfvars`. Dev uses
  account `995253610162`, `us-east-1`, three named AZs, `10.10.0.0/16`, the
  explicit global dev API CIDR, and the approved EKS access-entry role.

Confirm authentication through the team's normal identity flow. Do not export,
paste, or commit long-lived `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`
values.

## 2. Prepare local non-secret configuration

The two committed non-secret variable files are ready for team use:

```text
aws/environments/dev/backend/dev.tfvars
aws/environments/dev/foundation/dev.tfvars
```

Do not replace their values from local AWS CLI defaults. Dev intentionally uses
`0.0.0.0/0` for EKS API reachability because team IPs are dynamic; IAM and EKS
access entries authorize access. Do not silently narrow it, and do not reuse it
for staging or production. Dev reserves `10.10.0.0/16`; later staging and
production specs reserve `10.20.0.0/16` and `10.30.0.0/16` respectively.

After the backend is provisioned, create only the ignored
`aws/environments/dev/foundation/dev.s3.tfbackend` from its committed example.
It contains bucket, key, region, KMS key ARN, encryption, and native lockfile
settings only.

Configuration preparation is a prerequisite, not an internal module-navigation
step. Review the diff with a command that includes ignored files only in your
local shell; never force-add either file.

## 3. Generate and review the foundation plan

From the repository root, run exactly:

```bash
./scripts/aws-dev-foundation.sh check
./scripts/aws-dev-foundation.sh init
./scripts/aws-dev-foundation.sh validate
./scripts/aws-dev-foundation.sh plan
```

The entry point stops on the first error. A successful first plan must show only
the inventory in [the preview contract](./contracts/terraform-preview.md): one
dev VPC/EKS foundation, initial managed nodes, five ECR repositories, exact
IAM/IRSA resources, logging/encryption controls, and outputs. It must not show
Azure, staging, production, AKS, DynamoDB, Karpenter controllers/nodes, ArgoCD,
or Kubernetes application resources.

The plan is review evidence, not authorization to provision. Do not append a
Terraform apply command.

## 4. Review cost separately

The full profile deliberately includes three NAT gateways and stable On-Demand
bootstrap capacity. Make those costs visible with:

```bash
./scripts/aws-dev-foundation.sh cost
```

Cost pressure does not authorize changing to the single-cluster optimized
profile. That requires a constitution amendment and separate specification.

## Backend bootstrap preview

If the dev backend does not yet exist, stop the normal flow. The backend is a
separate root and review boundary. Its implementation documentation will expose
a backend-only check/init/validate/plan sequence using local state; creation and
state migration require separate authorization and are never triggered by
`aws-dev-foundation.sh`.

The backend plan must show one environment-qualified S3 bucket and KMS key with
versioning, public-access blocking, TLS enforcement, deletion protection, and
explicit operator permissions. It must not show a DynamoDB lock table.

## Expected failures

| Failure | Required response |
| --- | --- |
| Terraform or AWS CLI is missing/wrong version | `check` exits non-zero and names the prerequisite. |
| AWS session is absent/expired or account mismatches | Stop and re-authenticate through the approved short-lived flow. |
| Backend file/bucket/KMS key is missing | Stop; review the backend bootstrap boundary. |
| State lock is held | Identify the active operator; wait or use the incident-controlled lock procedure. |
| Region has fewer than three selected AZs or lacks EKS 1.35 | Choose another approved region/AZ set; do not silently downgrade topology/version. |
| Provisioning identity cannot read its own IAM role | Grant the reviewed execution role `iam:GetRole` on itself before a separately authorized provisioning run; do not broaden workload roles. |
| CIDRs overlap or dev API CIDR differs from the approved `0.0.0.0/0` | Stop for a reviewed decision; staging/production must use separate restricted policies. |
| ECR name already exists unmanaged | Stop for an explicit import-or-rename decision; do not auto-import. |
| Plan includes another environment or Azure | Treat as a contract failure and do not proceed. |

## GitOps handoff after later provisioning

After a separately approved implementation/provisioning lifecycle, operators
may inspect the non-secret `gitops_handoff` Terraform output. A future GitOps PR
maps it according to [the handoff contract](./contracts/gitops-registration-handoff.md).
Terraform does not create that PR, write registration files, install ArgoCD, or
apply Kubernetes manifests.

The later registration uses `server: https://kubernetes.default.svc`. The raw
EKS endpoint and certificate authority support kubeconfig and the audited
one-time ArgoCD/root bootstrap only.
