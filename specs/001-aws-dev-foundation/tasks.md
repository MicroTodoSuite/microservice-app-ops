---

description: "Dependency-ordered implementation tasks for the AWS dev foundation"
---

# Tasks: AWS Dev Foundation

**Input**: Design documents from `specs/001-aws-dev-foundation/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/`, and `quickstart.md`

**Tests**: Contract and mocked Terraform tests are required by SC-009 and are
listed before their corresponding implementation tasks.

**Organization**: Tasks are grouped by user story so each story remains
reviewable and testable without implementing another environment or mutating
GitOps.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it targets different files and does not
  depend on another incomplete task in the phase.
- **[Story]**: Maps the task to User Story 1, 2, or 3.
- Every task names the file or subtree it changes or validates.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the isolated AWS Terraform layout and reproducible
toolchain without altering the existing Azure roots.

- [x] T001 Update `.gitignore` to commit Terraform dependency lock files and the two approved non-secret dev tfvars while ignoring `aws/**/*.tfstate*`, saved plans, all other tfvars, and local `dev.s3.tfbackend`
- [x] T002 [P] Pin Terraform 1.15.8 for contributors in `.terraform-version`
- [x] T003 [P] Declare Terraform 1.15.8 and AWS provider 6.58.0 constraints in `aws/modules/environment-foundation/versions.tf`
- [x] T004 [P] Declare Terraform 1.15.8 and AWS provider 6.58.0 constraints in `aws/modules/state-backend/versions.tf`
- [x] T005 [P] Declare the backend-root Terraform and provider constraints in `aws/environments/dev/backend/versions.tf`
- [x] T006 [P] Declare the foundation-root Terraform/provider constraints and empty partial S3 backend in `aws/environments/dev/foundation/versions.tf` and `aws/environments/dev/foundation/backend.tf`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish account, provider, naming, and metadata guards used by
every story.

**⚠️ CRITICAL**: Complete this phase before user-story implementation.

- [x] T007 Configure AWS providers, caller-identity lookup, and expected-account preconditions in `aws/environments/dev/backend/providers.tf` and `aws/environments/dev/foundation/providers.tf`
- [x] T008 Define the canonical `microtodosuite`/`dev` naming inputs, required Platform ownership tags, approved principal validation, and non-overridable metadata in `aws/modules/environment-foundation/variables.tf`, `aws/modules/state-backend/variables.tf`, `aws/environments/dev/backend/variables.tf`, and `aws/environments/dev/foundation/variables.tf`

**Checkpoint**: Both independent roots reject the wrong AWS account and share
only naming/tag conventions; no Azure state or resource is referenced.

---

## Phase 3: User Story 1 - Preview an isolated dev foundation (Priority: P1) 🎯 MVP

**Goal**: Produce a complete, reviewable dev-only foundation plan from the
repository root in no more than four commands.

**Independent Test**: With approved local inputs and either a test backend or
backend-disabled mock mode, run the required tests and wrapper. The plan model
contains one three-AZ dev VPC, EKS 1.35 with stable bootstrap nodes, five ECR
repositories, exact IAM/OIDC resources, and no Azure/future-environment scope.

### Tests for User Story 1

> Write these tests first and confirm that they fail before implementing the
> corresponding Terraform resources and wrapper behavior.

- [x] T009 [P] [US1] Add a shell contract test for four-command dispatch, `-chdir` isolation, bounded locking, and absence of apply/destroy/kubectl paths in `tests/contract/aws-dev-foundation.sh`
- [x] T010 [P] [US1] Add mocked three-AZ VPC, private-worker, EKS 1.35, explicit dev API reachability, logging, and managed-node assertions in `aws/modules/environment-foundation/tests/network_eks.tftest.hcl`
- [x] T011 [P] [US1] Add mocked five-repository immutability/scanning/retention and exact CNI IRSA assertions in `aws/modules/environment-foundation/tests/ecr_irsa.tftest.hcl`
- [x] T012 [P] [US1] Add mocked dev-root inventory and Azure/staging/production/AKS exclusion assertions in `aws/environments/dev/foundation/tests/foundation.tftest.hcl`

### Implementation for User Story 1

- [x] T013 [US1] Complete VPC, subnet, AZ, endpoint CIDR, node capacity, access-entry, and five-service input validations in `aws/modules/environment-foundation/variables.tf`
- [x] T014 [US1] Implement the dedicated three-AZ VPC with VPC module 6.6.1, public/private subnet pairs, zonal NAT routes, load-balancer/Karpenter discovery tags, and encrypted VPC flow logging in `aws/modules/environment-foundation/network.tf`
- [x] T015 [US1] Implement the EKS 1.35 control plane with EKS module 21.24.2, private-plus-allowlisted-public API, secrets encryption, control-plane logs, API access entries, CoreDNS, kube-proxy, and VPC CNI in `aws/modules/environment-foundation/eks.tf`
- [x] T016 [US1] Add the AL2023 On-Demand managed node group using the account-compatible `m7i-flex.large` 2-vCPU/8-GiB baseline, replacement-safe `bootstrap-` physical-name prefix, encrypted gp3 launch template, IMDSv2, no-SSH posture, node repair, and `2/2/4` capacity bounds in `aws/modules/environment-foundation/eks.tf`
- [x] T017 [US1] Implement the EKS OIDC provider, exact `kube-system/aws-node` IRSA trust and CNI policy, limited worker-node permissions, and wildcard-subject rejection in `aws/modules/environment-foundation/irsa.tf`
- [x] T018 [US1] Implement the five `microtodosuite/dev/<service>` immutable AES-256 scan-on-push repositories and untagged-only lifecycle rules in `aws/modules/environment-foundation/ecr.tf`
- [x] T019 [US1] Export core network, cluster, node-group, ECR, OIDC, IRSA, and Karpenter-discovery values in `aws/modules/environment-foundation/outputs.tf`
- [x] T020 [US1] Compose only the environment-foundation module and dev account/region inputs in `aws/environments/dev/foundation/main.tf`, `aws/environments/dev/foundation/variables.tf`, and `aws/environments/dev/foundation/outputs.tf`
- [x] T021 [US1] Commit the human-approved account, `us-east-1` AZs, `10.10.0.0/16` subnet allocation, dev-only global API CIDR, and EKS administrator role in `aws/environments/dev/foundation/dev.tfvars`, retaining a clearly non-canonical reference example
- [x] T022 [US1] Implement fail-fast `check`, `init`, `validate`, `test`, `plan`, and `cost` dispatch with no mutation subcommand in `scripts/aws-dev-foundation.sh`
- [x] T023 [US1] Initialize the foundation root without its remote backend and commit the generated provider checksums in `aws/environments/dev/foundation/.terraform.lock.hcl`
- [x] T024 [US1] Run and fix the User Story 1 checks for `aws/modules/environment-foundation/`, `aws/environments/dev/foundation/`, `scripts/aws-dev-foundation.sh`, and `tests/contract/aws-dev-foundation.sh`

**Checkpoint**: User Story 1 can be demonstrated with mocked/backend-disabled
tests and, when a conforming backend is supplied, through the four-command live
preview. No apply operation is exposed.

---

## Phase 4: User Story 2 - Share protected, isolated state (Priority: P2)

**Goal**: Provide a separately bootstrapped, encrypted, recoverable, dev-only S3
state namespace with native lockfile concurrency protection.

**Independent Test**: Mocked tests prove the bucket/KMS/policy/address contract.
Against an already authorized test backend, a second plan cannot acquire the
held dev lock, and a generated future-environment address cannot equal dev.

### Tests for User Story 2

> Write these tests first and confirm that they fail before implementing the
> state module and bootstrap root.

- [ ] T025 [P] [US2] Add mocked bucket versioning, SSE-KMS, rotation, ownership, TLS denial, public-access blocking, deletion protection, and no-DynamoDB assertions in `aws/modules/state-backend/tests/state_backend.tftest.hcl`
- [ ] T026 [P] [US2] Add mocked dev bucket/key/account/address isolation and approved-principal assertions in `aws/environments/dev/backend/tests/backend.tftest.hcl`
- [ ] T027 [P] [US2] Add static state-key, lock-key, permission, ignored-secret-file, and recovery-document contract checks in `tests/contract/aws-dev-state.sh`

### Implementation for User Story 2

> **Narrow bootstrap slice (2026-08-09)**: Only the bucket/KMS resource set,
> backend-root composition, partial native-lock configuration, and local
> provider lock are implemented in this pass. T028 remains open for its
> approved-principal validation and T031 remains open for its policy ARN. T033
> now records the approved account/region inputs; IAM grants, recovery/migration
> procedures, and every backend test remain deliberately deferred.

- [ ] T028 [US2] Complete bucket naming, account/region, approved operator role, key-prefix, and tag validations in `aws/modules/state-backend/variables.tf`
- [x] T029 [US2] Implement the dev S3 bucket, versioning, owner enforcement, all public-access blocks, TLS-only policy, rotating KMS key, SSE-KMS defaults, and lifecycle protection in `aws/modules/state-backend/main.tf`
- [ ] T030 [US2] Implement prefix-scoped state/lock/version/KMS permissions with no state-object delete and no workload principals in `aws/modules/state-backend/iam.tf`
- [ ] T031 [US2] Export the bucket, KMS ARN, bootstrap key, foundation key, lock key, and approved backend policy ARN in `aws/modules/state-backend/outputs.tf`
- [x] T032 [US2] Compose only the state-backend module with dev constants and account guard in `aws/environments/dev/backend/main.tf`, `aws/environments/dev/backend/variables.tf`, and `aws/environments/dev/backend/outputs.tf`
- [x] T033 [US2] Commit the human-approved non-secret dev backend account and `us-east-1` inputs in `aws/environments/dev/backend/dev.tfvars`, retaining a clearly non-canonical reference example; operator-policy inputs remain deferred with T030
- [x] T034 [US2] Add the credential-free native-lock partial backend example for `environments/dev/foundation/terraform.tfstate` in `aws/environments/dev/foundation/dev.s3.tfbackend.example`
- [ ] T035 [US2] Document local backend bootstrap, separately reviewed state migration, lock ownership checks, and version recovery without embedding state or credentials in `aws/environments/dev/backend/README.md`
- [ ] T036 [US2] Add an explicit opt-in, non-mutating two-writer lock integration check for an already provisioned test backend in `tests/integration/aws-dev-state-lock.sh`
- [x] T037 [US2] Initialize the backend root locally and commit the generated provider checksums in `aws/environments/dev/backend/.terraform.lock.hcl`
- [ ] T038 [US2] Run and fix the User Story 2 checks for `aws/modules/state-backend/`, `aws/environments/dev/backend/`, `tests/contract/aws-dev-state.sh`, and `tests/integration/aws-dev-state-lock.sh`

**Checkpoint**: State resources can be reviewed and bootstrapped independently;
normal foundation planning uses an isolated S3 key and `.tflock`, never a new
DynamoDB table.

---

## Phase 5: User Story 3 - Hand off cleanly to GitOps (Priority: P3)

**Goal**: Publish non-secret infrastructure values that fit the implemented
per-cluster registration seam without Terraform editing GitOps or inventing a
central-Argo remote-server contract.

**Independent Test**: Mock and contract checks compare the output object to the
actual sibling `clusters/local-kind` registration/activation structure. They
verify in-cluster activation, derived namespace, five ECR URLs, absent
Git-owned values, and explicit current GitOps gaps.

### Tests for User Story 3

> Write these tests first and confirm that they fail before adding the structured
> output.

- [ ] T039 [P] [US3] Add mocked `gitops_handoff` schema, fixed value, five-service map, and absent Git-owned-field assertions in `aws/environments/dev/foundation/tests/gitops_handoff.tftest.hcl`
- [ ] T040 [P] [US3] Add a read-only sibling-contract check for registration data, dual activation lists, derived namespace, in-cluster destinations, and known wiring/conformance/documentation gaps in `tests/contract/aws-dev-gitops-handoff.sh`

### Implementation for User Story 3

- [ ] T041 [US3] Complete the module exports needed for bootstrap/operator access, exact IRSA consumers, ECR overlays, and future Karpenter discovery in `aws/modules/environment-foundation/outputs.tf`
- [ ] T042 [US3] Implement the typed non-sensitive `gitops_handoff` object with `dev`, `microtodo-dev`, `https://kubernetes.default.svc`, EKS endpoint/CA, ECR URLs, OIDC/IRSA, and discovery values in `aws/environments/dev/foundation/outputs.tf`
- [ ] T043 [US3] Document the output-to-registration mapping, per-cluster bootstrap boundary, digest ownership, the corrected five-root inventory, and the two remaining GitOps gaps in `aws/environments/dev/foundation/README.md`
- [ ] T044 [US3] Run and fix the User Story 3 checks for `aws/environments/dev/foundation/tests/gitops_handoff.tftest.hcl`, `tests/contract/aws-dev-gitops-handoff.sh`, and `aws/environments/dev/foundation/README.md`

**Checkpoint**: The foundation handoff needs no Terraform-output redesign when
GitOps later resolves its own value-only wiring, conformance fixture, add-on
inventory mismatch, and central-versus-per-cluster documentation conflict.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Complete CI, cost, security, and operator documentation across all
stories without provisioning resources.

- [ ] T045 [P] Configure the dev foundation project, input examples, and three-NAT/two-node cost visibility in `infracost.yml`
- [ ] T046 [P] Add pinned formatting, backend-free validation, mocked Terraform tests, ShellCheck, contract tests, Trivy config scanning, and Infracost validation without AWS static credentials or apply steps in `.github/workflows/aws-dev-foundation-checks.yml`
- [ ] T047 [P] Add the AWS dev architecture, separate-backend boundary, four-command preview, ownership split, and links to `specs/001-aws-dev-foundation/quickstart.md` in `README.md`
- [ ] T048 Run Terraform formatting/initialization/validation/tests, ShellCheck, all `tests/contract/aws-dev-*.sh`, and Trivy against `aws/`, `scripts/aws-dev-foundation.sh`, and `.github/workflows/aws-dev-foundation-checks.yml`
- [ ] T049 In an approved account with an already conforming backend, run the four-command non-mutating preview and record inventory, lock, account, cost, and zero-Azure/future-environment evidence in `specs/001-aws-dev-foundation/checklists/acceptance.md`
- [ ] T050 Reconcile implemented paths and commands back into `specs/001-aws-dev-foundation/quickstart.md`, verify the known diagram/GitOps discrepancies remain explicit in `specs/001-aws-dev-foundation/research.md`, and run whitespace/diff checks across `specs/001-aws-dev-foundation/`

---

## Phase 7: Post-Provisioning Security Remediation

**Purpose**: Close the observed gap between GitOps-owned namespace policies and
the Terraform-owned VPC CNI enforcement switch without mutating the cluster in
this implementation pass.

- [x] T051 [US1] Add the versioned `enableNetworkPolicy = "true"` VPC CNI
  managed-add-on configuration, regression assertions, ownership documentation,
  and the pre-apply runtime baseline in
  `aws/modules/environment-foundation/eks.tf`, its tests, and the US1 artifacts
- [ ] T052 [US1] After the approved execution role receives the documented IAM
  refresh permissions, run a refresh-backed no-apply plan and confirm that it
  proposes only the expected in-place VPC CNI configuration update
- [ ] T053 [US1] After a separately authorized apply, use read-only cluster
  inspection to confirm every ready `aws-node` pod has a ready
  `aws-eks-nodeagent` container with `--enable-network-policy=true`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependency; T002-T006 may run in parallel after the
  repository status is confirmed.
- **Foundational (Phase 2)**: Depends on Setup and blocks all user stories.
- **User Story 1 (Phase 3)**: Depends on Foundational. Its tests can use mocked
  providers/backend-disabled initialization without User Story 2.
- **User Story 2 (Phase 4)**: Depends on Foundational and can be developed in
  parallel with User Story 1 because it owns a separate module/root.
- **User Story 3 (Phase 5)**: Its tests can be written after Foundational, but
  T041-T044 depend on the core outputs from T019-T020 in User Story 1.
- **Polish (Phase 6)**: T045-T047 can begin after their referenced files exist;
  T048-T050 depend on all selected user stories. The live preview in T049 also
  requires an already provisioned conforming backend and explicit account
  authorization, but never runs an apply.
- **Post-Provisioning Security Remediation (Phase 7)**: T051 depends on the
  provisioned US1 EKS add-on; T052 depends on the execution-role read permissions,
  and T053 depends on a separately authorized apply.

### User Story Dependencies

- **User Story 1 (P1)**: Independently proves the complete foundation shape and
  operator interface through mock/backend-disabled tests. A real remote plan
  accepts any backend that satisfies the published contract.
- **User Story 2 (P2)**: Independently delivers that backend contract and does
  not depend on VPC/EKS/ECR resources.
- **User Story 3 (P3)**: Contract/schema tests are independent; final output
  composition consumes User Story 1's module outputs and never consumes state
  implementation details from User Story 2.

### Within Each User Story

- Write the story tests first and confirm that they fail for the intended
  missing behavior.
- Implement input/resource policy before root composition and outputs.
- Generate dependency locks only after provider/module constraints are final.
- Complete the story checkpoint before treating later integration as evidence.
- Do not run or add an apply path while executing this task list.

## Parallel Opportunities

- T002-T006 establish different files and can run in parallel.
- T009-T012 can be written in parallel before User Story 1 implementation.
- T014, T017, and T018 target separate module files after T013 and can proceed
  in parallel; T015-T016 share `eks.tf` and stay sequential.
- T025-T027 can be written in parallel; T030 can proceed separately after the
  state input schema from T028 is stable.
- T039 and T040 can be written in parallel.
- User Stories 1 and 2 can be implemented by separate contributors after Phase
  2; User Story 3's contract test can also begin then.
- T045-T047 target independent cross-cutting files and can run in parallel.

## Parallel Example: User Story 1

```text
Task T010: Add network/EKS mocked tests in aws/modules/environment-foundation/tests/network_eks.tftest.hcl
Task T011: Add ECR/IRSA mocked tests in aws/modules/environment-foundation/tests/ecr_irsa.tftest.hcl
Task T012: Add root inventory tests in aws/environments/dev/foundation/tests/foundation.tftest.hcl
```

After T013 stabilizes inputs:

```text
Task T014: Implement networking in aws/modules/environment-foundation/network.tf
Task T017: Implement IRSA in aws/modules/environment-foundation/irsa.tf
Task T018: Implement ECR in aws/modules/environment-foundation/ecr.tf
```

## Parallel Example: User Story 2

```text
Task T025: Add state module tests in aws/modules/state-backend/tests/state_backend.tftest.hcl
Task T026: Add backend root tests in aws/environments/dev/backend/tests/backend.tftest.hcl
Task T027: Add state contract tests in tests/contract/aws-dev-state.sh
```

## Parallel Example: User Story 3

```text
Task T039: Add Terraform handoff tests in aws/environments/dev/foundation/tests/gitops_handoff.tftest.hcl
Task T040: Add sibling GitOps contract checks in tests/contract/aws-dev-gitops-handoff.sh
```

## Implementation Strategy

### MVP First

1. Complete Setup and Foundational phases.
2. Complete User Story 1 and prove the foundation shape in mock/backend-disabled
   mode.
3. Stop and review the MVP before introducing state or GitOps integration.
4. For an operational remote preview, supply any pre-existing backend that
   satisfies `contracts/remote-state.md` or add User Story 2.

### Incremental Delivery

1. **US1**: Dev foundation topology, identity, registry, and safe preview CLI.
2. **US2**: Team-safe isolated backend and recovery/locking contract.
3. **US3**: Actual per-cluster GitOps handoff values and drift visibility.
4. **Polish**: CI, Infracost, root documentation, and non-mutating acceptance
   evidence.

Each increment preserves the existing Azure roots and can stop at its checkpoint.

## Notes

- `[P]` means different files and no hidden dependency on an incomplete task.
- Story labels provide requirement traceability; Setup, Foundational, and Polish
  tasks intentionally have no story label.
- All Kubernetes workloads/add-ons remain GitOps-owned; no task writes to
  `../microservice-app-gitops`.
- The task list ends at code, tests, reviewable plan, and evidence. External
  infrastructure provisioning requires separate authorization and is not an
  implicit implementation step.
