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
