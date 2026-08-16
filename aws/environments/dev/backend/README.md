# Dev Terraform State Bootstrap

This root is the narrow, one-time exception that creates the storage required
by Terraform before Terraform can use remote state. It intentionally uses the
local backend declared in `backend.tf`; no other MicroTodoSuite Terraform root
that consumes infrastructure may adopt this exception. Any future environment
backend would need its own explicitly reviewed bootstrap boundary. This mirrors
the constitution's minimal one-time GitOps controller/root bootstrap: create
only the prerequisite needed to enter the normal reconciled workflow, then stop
using the exception.

This increment provisions only the dev S3 state bucket, its rotating KMS key,
bucket versioning, owner enforcement, public-access blocking, TLS enforcement,
and default SSE-KMS. Native state locking is enabled later by the foundation
backend's `use_lockfile = true`; Terraform creates and removes
`environments/dev/foundation/terraform.tfstate.tflock` during locked operations.
No DynamoDB lock table is used.

## Review the bootstrap plan

The root's committed `dev.tfvars` contains the human-approved non-secret account
and `us-east-1` values. From the repository root, run:

```bash
terraform -chdir=aws/environments/dev/backend init
terraform -chdir=aws/environments/dev/backend validate
terraform -chdir=aws/environments/dev/backend plan -input=false -var-file=dev.tfvars
```

These commands only initialize, validate, and plan. They do not create the
bucket. Provisioning requires a separate, explicitly authorized apply review;
this repository's normal foundation wrapper has no apply path.

Until a later reviewed migration moves this root to
`environments/dev/backend-bootstrap/terraform.tfstate`, its local
`terraform.tfstate` is the sole ownership record for the bucket and KMS key.
It is ignored by Git, must not be copied into logs or commits, and must be kept
access-controlled. Do not delete it after provisioning.

## Configure the foundation only after provisioning

After the bucket exists, copy the non-secret output values into
`../foundation/dev.s3.tfbackend` from its committed example. The foundation's
approved `dev.tfvars` is already committed; then run:

```bash
terraform -chdir=aws/environments/dev/foundation init \
  -reconfigure \
  -backend-config=dev.s3.tfbackend
```

Do not run that command before `HeadBucket` confirms the bucket exists. This
increment deliberately defers operator/automation IAM access policies, the
backend-root state migration, lock incident and version-recovery procedures,
and backend tests to the later US2/US3 pass.

## Namespace-isolation Terraform execution policy

Feature 005 extends the existing foundation with five additive neutral ECR
repositories, three environment JWT secrets and reader roles, one exact GitHub
OIDC publisher role, and one Kyverno verifier role. Terraform must continue to
run as `microtodosuite-terraform-dev`; a personal IAM user is not an approved
substitute.

The refresh-backed plan executed on 2026-08-16 authenticated as
`arn:aws:sts::995253610162:assumed-role/microtodosuite-terraform-dev/*` and
failed without producing an applicable plan because the role lacks
`iam:ListRolePolicies` on
`arn:aws:iam::995253610162:role/vpc-flow-log-role-*`. A direct read also proved
that `iam:ListOpenIDConnectProviders` is absent. `PowerUserAccess` intentionally
does not grant the IAM write operations needed for the five narrowly named
feature roles or the exact GitHub OIDC provider.

The reviewed bootstrap input is
`namespace-isolation-terraform-execution-policy.json`. It grants:

- read-only Terraform refresh actions on current `microtodosuite-dev-*` and
  `vpc-flow-log-role-*` roles;
- lifecycle and inline-policy management only for the three exact JWT reader
  roles, the GitHub ECR publisher role, and the Kyverno ECR verifier role; and
- discovery plus lifecycle management only for
  `token.actions.githubusercontent.com` as an IAM OIDC provider.

An account IAM administrator must attach it as an inline policy to the intended
Terraform role through the audited bootstrap path:

```bash
aws iam put-role-policy \
  --role-name microtodosuite-terraform-dev \
  --policy-name namespace-isolation-release-prerequisites \
  --policy-document file://aws/environments/dev/backend/namespace-isolation-terraform-execution-policy.json \
  --profile <approved-iam-administrator-profile>
```

The locally configured `esteban-personal` identity is not sufficient evidence:
as observed on 2026-08-16 it has only `IAMUserChangePassword`. Do not broaden
that user or attach administrator access merely to bypass this bootstrap.

After the administrator records the policy attachment, verify the intended role
without applying infrastructure:

```bash
AWS_PROFILE=microtodosuite-terraform ./scripts/aws-dev-foundation.sh check
AWS_PROFILE=microtodosuite-terraform ./scripts/aws-dev-foundation.sh init
AWS_PROFILE=microtodosuite-terraform ./scripts/aws-dev-foundation.sh plan
```

The final command must complete a refresh-backed plan without `AccessDenied`.
Any additional IAM denial must be added narrowly to this reviewed policy and
re-reviewed; it must not be worked around with `-refresh=false` or another
caller.
