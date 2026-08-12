# Contract: Dev Remote State

## Purpose

Define how the platform team bootstraps, addresses, locks, authorizes, recovers,
and later reuses the dev Terraform state without allowing another environment
or workload to collide with it.

## Ownership boundary

- `aws/environments/dev/backend` owns the dev state bucket, KMS key, bucket
  policy, and approved backend-principal policy.
- `aws/environments/dev/foundation` consumes that backend through partial S3
  configuration and never attempts to create or modify it.
- Existing Azure Blob backends and Azure roots remain unrelated.
- GitOps workloads and cluster service accounts have no state access.

## Canonical addresses

| Item | Contract |
| --- | --- |
| Bucket | `microtodosuite-tfstate-<account-id>-<region>-dev` after normalization and AWS name validation |
| Foundation state | `environments/dev/foundation/terraform.tfstate` |
| Foundation lock | `environments/dev/foundation/terraform.tfstate.tflock` |
| Backend-bootstrap state after migration | `environments/dev/backend-bootstrap/terraform.tfstate` |
| Encryption | Dedicated rotating customer-managed KMS key for the dev backend |

A future environment must have both a different environment-qualified bucket
and different keys. Terraform workspaces are not the isolation mechanism.

## Partial backend configuration

`aws/environments/dev/foundation/backend.tf` declares only `backend "s3" {}`.
The committed `dev.s3.tfbackend.example` documents these non-secret fields:

```hcl
bucket         = "microtodosuite-tfstate-<account-id>-<region>-dev"
key            = "environments/dev/foundation/terraform.tfstate"
region         = "<aws-region>"
encrypt        = true
kms_key_id     = "<dev-state-kms-key-arn>"
use_lockfile   = true
```

The local file used by operators is ignored. It must not contain access keys,
session tokens, profile secrets, role credentials, or a DynamoDB table field.
Credentials come from the approved short-lived AWS authentication chain.

## Bucket and KMS controls

The backend plan must show all of the following before it is eligible for a
separate provisioning review:

- S3 versioning enabled.
- All four S3 public-access block settings enabled.
- Bucket-owner-enforced object ownership and ACLs disabled.
- Default SSE-KMS using the dedicated key; key rotation enabled.
- Bucket policy denies requests that do not use TLS.
- `force_destroy = false` and lifecycle protection on the bucket and KMS key.
- Required project, environment, owner, and managed-by metadata.
- No lifecycle expiration of current or noncurrent state versions.

## Authorization contract

Approved operator/automation roles receive only the backend permissions required
for their reviewed duties:

- List the bucket only for the two dev state prefixes.
- Read and write the relevant state object.
- Read, create, and delete only the matching `.tflock` object.
- Use the KMS key for the corresponding encrypted S3 operations.
- Read bucket version metadata for recovery.

The policy does not grant deletion of the foundation state object. It does not
grant any application, node, IRSA workload, or unrelated environment role
access. The Terraform roots verify `expected_account_id` against the current
caller identity before resource planning.

## Bootstrap contract

1. Initialize and plan the backend root with local state only.
2. Review the dedicated bucket/KMS plan independently from the foundation.
3. After a separately authorized provisioning action creates the backend,
   capture its non-secret outputs in the local partial backend configuration.
4. Review and perform an explicit state migration of the backend root to its
   bootstrap key. Preserve the pre-migration local state as an access-controlled
   recovery artifact until migration is verified.
5. Only then initialize and plan the foundation root against remote state.

The foundation wrapper must detect a missing or wrong backend and fail; it must
not bootstrap or migrate state implicitly.

## Locking behavior

- Every foundation plan uses `use_lockfile = true` and a bounded non-zero lock
  timeout.
- If one writer holds the lock, a second writer exits without writing state.
- The lock object shares the exact state prefix and cannot collide with later
  environment locks.
- Interrupted-operation handling first identifies the lock owner and active
  operation. A lock is never automatically deleted based only on age.
- Force-unlock or direct lock-object deletion requires incident evidence and an
  approved operator; a new plan follows before any further mutation.

## Recovery behavior

Recovery documentation and tests must demonstrate that an approved operator can:

1. List object versions without exposing state contents in logs.
2. Identify the last known-good version and the event that replaced it.
3. Restore that version as the current encrypted object under change review.
4. Run a fresh locked plan and confirm the expected infrastructure inventory.

Version recovery does not bypass locking, account checks, or review. Logs and CI
artifacts must not publish Terraform state, backend credentials, or decrypted
secrets.

## Contract tests

- Static/mocked tests assert all bucket, KMS, policy, versioning, and public
  access invariants without cloud mutation.
- A separately authorized integration test holds the dev lock and verifies a
  second writer cannot acquire it.
- Address tests generate later-environment examples and prove neither state nor
  lock keys equal the dev values.
- Recovery evidence records version identifiers and a successful post-recovery
  plan, not state contents.

## Diagram reconciliation

Both Eraser diagrams show S3 plus DynamoDB for state and locking. S3 remains the
remote state store, but DynamoDB locking is intentionally not implemented:
Terraform's native S3 lockfile is the current mechanism and satisfies the same
concurrency requirement with less obsolete infrastructure.
