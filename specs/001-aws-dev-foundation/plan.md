# Implementation Plan: AWS Dev Foundation

**Branch**: `esteban/eks-dev-foundation` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/001-aws-dev-foundation/spec.md`

## Summary

Add a new `aws/` Terraform layout beside the independently operable Azure
roots. The dev root will compose a dedicated three-AZ VPC, EKS 1.35, a stable
On-Demand managed node group, five hardened ECR repositories, EKS OIDC and an
exact IRSA binding for the VPC CNI. A separate bootstrap root creates a
dev-specific S3/KMS backend with versioning and Terraform's native S3 lockfile.
A repository-root wrapper will make init, validation, testing, cost review, and
plan generation discoverable without applying infrastructure.

The foundation exposes a typed GitOps handoff, but does not mutate the sibling
GitOps repository. It follows the current per-cluster ArgoCD implementation:
the EKS endpoint and certificate authority support operator access and the
audited one-time bootstrap, while activation uses
`https://kubernetes.default.svc`.

## Technical Context

**Language/Version**: Terraform `1.15.8`; HCL; Bash compatible with Bash 5+

**Primary Dependencies**: AWS provider `6.58.0`; terraform-aws-modules/vpc/aws
`6.6.1`; terraform-aws-modules/eks/aws `21.24.2`; AWS CLI v2 for authenticated
operator checks; Trivy, ShellCheck, and Infracost for review gates

**Storage**: Amazon S3 remote state with a dedicated dev bucket, SSE-KMS,
versioning, public-access blocking, and `use_lockfile = true`; no DynamoDB table

**Testing**: `terraform fmt -check -recursive`; backend-free `terraform init`
and `terraform validate`; mocked `terraform test`; ShellCheck; repository
contract tests; Trivy configuration scan; Infracost breakdown

**Target Platform**: AWS account `995253610162`, region `us-east-1`, and
availability zones `us-east-1a`, `us-east-1b`, and `us-east-1c`; Linux operator
and CI runners

**Project Type**: Infrastructure as code with independent Terraform roots and a
thin repository-root operator CLI

**Performance Goals**: A teammate reaches a complete dev plan in at most four
documented commands; a lock conflict fails before state mutation; unchanged
inputs and state converge to an empty follow-up plan

**Constraints**: No `terraform apply`, GitOps mutation, direct `kubectl apply`,
staging/production/AKS resources, static AWS keys, wildcard IRSA subjects,
mutable ECR tags, DynamoDB lock table, or changes to existing Azure state

**Scale/Scope**: One dev VPC, three availability zones, one EKS cluster, one
managed node group (`min=2`, `desired=2`, `max=4`), five ECR repositories, one
state bucket/KMS key, and exact IAM identities needed by this foundation

## Constitution Check

*GATE: Passed before Phase 0 research and re-checked after Phase 1 design.*

| Principle | Result | Design evidence |
| --- | --- | --- |
| 1. Environment Isolation | PASS | Dev receives its own VPC, EKS cluster, remote-state namespace, and environment-qualified names; no namespace-only cost profile is adopted. |
| 2. GitOps-Only Deployment | PASS | Terraform creates only AWS foundation resources. The plan documents but does not perform the constitution's one-time ArgoCD bootstrap exception. |
| 3. Stable Trunk Development | PASS | Work remains on the short-lived feature branch and is structured for reviewed checks before merge. |
| 4. Authoritative Specifications | PASS | `spec.md`, clarifications, this plan, contracts, and generated tasks define the implementation. |
| 5. Cost-Governed Design | PASS | Three NAT gateways and managed nodes remain visible; Infracost is a required review gate instead of silently selecting the economical profile. |
| 6. Immutable Build Promotion | PASS | ECR rejects tag replacement and the handoff explicitly reserves OCI digest selection for GitOps. |
| 7. Progressive and Reversible Releases | PASS | Application release behavior is outside this foundation; no direct deployment path is added. |
| 8. Quality and Supply-Chain Gates | PASS | Terraform tests, contract checks, Trivy, ShellCheck, and formatting/validation gates are planned. Image build gates remain owned by service/shared CI. |
| 9. Observable and Resilient Operations | PASS | EKS control-plane logs, three-AZ network placement, and multi-AZ bootstrap capacity are planned; workload observability stays GitOps-owned. |
| 10. Least Privilege and Secret Hygiene | PASS | Short-lived operator credentials, exact IRSA subjects, exact EKS access entries, private workers, and no committed secrets remain required. Dev's human-approved global API reachability is identity-controlled and explicitly forbidden as a staging/production precedent. |
| 11. Declarative and Policy-Controlled Platform | PASS | Terraform owns VPC/EKS/IAM/IRSA/ECR/state; ArgoCD retains add-ons, applications, activation, and overlays. |
| 12. Proven DR and Disclosed Data Loss | PASS | No DR claim or data-continuity change is made; AKS and cross-cloud routing are explicitly excluded. |

No constitutional exception or complexity waiver is required.

## Project Structure

### Documentation (this feature)

```text
specs/001-aws-dev-foundation/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── gitops-registration-handoff.md
│   ├── remote-state.md
│   └── terraform-preview.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
aws/
├── modules/
│   ├── environment-foundation/
│   │   ├── versions.tf
│   │   ├── variables.tf
│   │   ├── network.tf
│   │   ├── eks.tf
│   │   ├── ecr.tf
│   │   ├── irsa.tf
│   │   ├── outputs.tf
│   │   └── tests/
│   │       ├── ecr_irsa.tftest.hcl
│   │       └── network_eks.tftest.hcl
│   └── state-backend/
│       ├── versions.tf
│       ├── variables.tf
│       ├── main.tf
│       ├── iam.tf
│       ├── outputs.tf
│       └── tests/state_backend.tftest.hcl
└── environments/
    └── dev/
        ├── backend/
        │   ├── versions.tf
        │   ├── providers.tf
        │   ├── variables.tf
        │   ├── main.tf
        │   ├── outputs.tf
        │   ├── dev.tfvars
        │   ├── dev.tfvars.example
        │   ├── README.md
        │   ├── .terraform.lock.hcl
        │   └── tests/backend.tftest.hcl
        └── foundation/
            ├── backend.tf
            ├── versions.tf
            ├── providers.tf
            ├── variables.tf
            ├── main.tf
            ├── outputs.tf
            ├── dev.s3.tfbackend.example
            ├── dev.tfvars
            ├── dev.tfvars.example
            ├── README.md
            ├── .terraform.lock.hcl
            └── tests/
                ├── foundation.tftest.hcl
                └── gitops_handoff.tftest.hcl

scripts/
└── aws-dev-foundation.sh

tests/
├── contract/
│   ├── aws-dev-foundation.sh
│   ├── aws-dev-gitops-handoff.sh
│   └── aws-dev-state.sh
└── integration/
    └── aws-dev-state-lock.sh

.github/workflows/
└── aws-dev-foundation-checks.yml

infracost.yml

.terraform-version
```

Each Terraform root commits its own `.terraform.lock.hcl` and its approved,
non-secret dev inputs. `.gitignore` allows those exact files while continuing
to ignore state, saved plans, credentials, local backend configuration, and all
other variable files.

**Structure Decision**: The new `aws/` subtree prevents the AWS state and
provider graph from coupling to the existing `backend/`,
`base-infrastructure/`, and `container-apps/` Azure roots. Reusable modules own
resource policy; the two dev roots own backend bootstrapping and foundation
composition. The wrapper is the supported teammate entry point, so internal
module paths are implementation detail.

## Phase 0: Research Conclusions

The binding choices and rejected alternatives are recorded in
[research.md](./research.md). The important outcomes are EKS 1.35, a three-AZ
full-profile topology, exact IRSA, stable managed bootstrap nodes, immutable
ECR, native S3 locking, and per-cluster ArgoCD handoff semantics.

## Phase 1: Design and Contracts

- [data-model.md](./data-model.md) defines inputs, resources, invariants,
  outputs, and lifecycle states.
- [remote-state.md](./contracts/remote-state.md) defines bootstrap, isolation,
  locking, authorization, and recovery behavior.
- [terraform-preview.md](./contracts/terraform-preview.md) defines the supported
  operator command surface and non-mutation guarantees.
- [gitops-registration-handoff.md](./contracts/gitops-registration-handoff.md)
  maps Terraform outputs to the actual GitOps registration and records the
  current GitOps gaps.
- [quickstart.md](./quickstart.md) gives the future teammate workflow without an
  apply command.

## Complexity Tracking

No constitution violations require justification.
