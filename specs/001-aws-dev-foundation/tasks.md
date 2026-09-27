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

**Layout reconciliation, 2026-09-27.** The maintainer delegated this
decision to the lead on 2026-09-21. Ops spec 004 replaced the layout that most
open tasks of Phases 4 to 8 target: the legacy `aws/environments/dev/{backend,foundation}`
roots and the local `state-backend` and `environment-foundation` modules gave
way to the `shd`, `eco`, `fdev`, `fstg`, and `fprd` domain roots, which consume
released modules from `terraform-aws-modules` (ops spec 004 T009-T012) and were
applied on 2026-09-14 (T020). `aws/environments/shd/state/README.md` records
that it replaces `aws/environments/dev/backend`, and the header of
`.github/workflows/iac-checks.yml` records that the legacy roots are replaced by
the rebuilt ones. The legacy roots remain on `main` only because the dev
foundation state still holds the old persistent resources until ops spec 004
T026 deletes them; no further work targets them.

Following the precedent of microservice-app-gitops spec 009 T056, T061, and
T062, T025-T028, T030, T031, T035, T036, T038-T050, T052, and T060 stay
unchecked, and each carries a **Superseded by** note naming its successor. Where
the successor does not cover part of the original task, the note says so; that
part needs its own task in the owning specification, not a hidden extension of
the legacy roots. T053 is not superseded: its live node-agent check applies to
the rebuilt cluster and stays open.

The 2026-09-27 delivery audit reported the files these tasks name as absent.
Some of them exist: `aws/modules/state-backend/variables.tf` and `outputs.tf`,
`aws/environments/dev/backend/README.md`, the two `outputs.tf` files that T041
and T042 name, `.github/workflows/aws-dev-foundation-checks.yml`, `README.md`,
`quickstart.md`, and `research.md`. They belong to the retired layout. The
supersession rests on the layout decision, not on their absence.

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

**Critical**: Complete this phase before user-story implementation.

- [x] T007 Configure AWS providers, caller-identity lookup, and expected-account preconditions in `aws/environments/dev/backend/providers.tf` and `aws/environments/dev/foundation/providers.tf`
- [x] T008 Define the canonical `microtodosuite`/`dev` naming inputs, required Platform ownership tags, approved principal validation, and non-overridable metadata in `aws/modules/environment-foundation/variables.tf`, `aws/modules/state-backend/variables.tf`, `aws/environments/dev/backend/variables.tf`, and `aws/environments/dev/foundation/variables.tf`

**Checkpoint**: Both independent roots reject the wrong AWS account and share
only naming/tag conventions; no Azure state or resource is referenced.

---

## Phase 3: User Story 1 - Preview an isolated dev foundation (Priority: P1), MVP

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

- [ ] T025 [P] [US2] Add mocked bucket versioning, SSE-KMS, rotation, ownership, TLS denial, public-access blocking, deletion protection, and no-DynamoDB assertions in `aws/modules/state-backend/tests/state_backend.tftest.hcl` — **Superseded by ops spec 004 T009:** the released `state-backend-v1.0.0` module in `terraform-aws-modules` carries `state-backend/tests/state_backend.tftest.hcl`, which asserts versioning, `BucketOwnerEnforced`, all four public-access blocks, a rotating KMS key with SSE-KMS and bucket keys, TLS denial, and `force_destroy = false`; locking is S3-native (`use_lockfile = true`), so there is no DynamoDB table to assert against
- [ ] T026 [P] [US2] Add mocked dev bucket/key/account/address isolation and approved-principal assertions in `aws/environments/dev/backend/tests/backend.tftest.hcl` — **Superseded by ops spec 004 T010:** `aws/environments/shd/state/tests/state.tftest.hcl` asserts the bucket and key names and rejects an environment other than `shd`, an account that is not twelve digits, and a deploy principal that is not a role
- [ ] T027 [P] [US2] Add static state-key, lock-key, permission, ignored-secret-file, and recovery-document contract checks in `tests/contract/aws-dev-state.sh` — **Superseded by ops spec 004 T008 and T010:** state-key isolation is enforced by the `State keys stay distinct` job of `.github/workflows/aws-full-foundation-checks.yml` over every committed backend example, and naming by `tests/contract/rebuilt-plan-contracts.sh`; no successor carries the lock-key, permission, ignored-secret-file, or recovery-document checks

### Implementation for User Story 2

> **Narrow bootstrap slice (2026-08-09)**: Only the bucket/KMS resource set,
> backend-root composition, partial native-lock configuration, and local
> provider lock are implemented in this pass. T028 remains open for its
> approved-principal validation and T031 remains open for its policy ARN. T033
> now records the approved account/region inputs; IAM grants, recovery/migration
> procedures, and every backend test remain deliberately deferred.

- [ ] T028 [US2] Complete bucket naming, account/region, approved operator role, key-prefix, and tag validations in `aws/modules/state-backend/variables.tf` — **Superseded by ops spec 004 T009 and T010:** the bucket-name and KMS-window validations live in `state-backend-v1.0.0`, and the account, environment, and deploy-principal validations in `aws/environments/shd/state/variables.tf`
- [x] T029 [US2] Implement the dev S3 bucket, versioning, owner enforcement, all public-access blocks, TLS-only policy, rotating KMS key, SSE-KMS defaults, and lifecycle protection in `aws/modules/state-backend/main.tf`
- [ ] T030 [US2] Implement prefix-scoped state/lock/version/KMS permissions with no state-object delete and no workload principals in `aws/modules/state-backend/iam.tf` — **Superseded by ops spec 004 T010:** operators reach state through the Terraform deploy role `lex-mts-shd-role-tfdeploy` in `aws/environments/shd/security`; the prefix-scoped, no-delete state policy this task describes was not carried over and has no successor task
- [ ] T031 [US2] Export the bucket, KMS ARN, bootstrap key, foundation key, lock key, and approved backend policy ARN in `aws/modules/state-backend/outputs.tf` — **Superseded by ops spec 004 T010:** `aws/environments/shd/state/outputs.tf` exports the bucket name and ARN and the KMS key ARN and alias; state keys follow `<environment>/<domain>/terraform.tfstate` (ops spec 004 plan), and no backend policy ARN exists to export (see T030)
- [x] T032 [US2] Compose only the state-backend module with dev constants and account guard in `aws/environments/dev/backend/main.tf`, `aws/environments/dev/backend/variables.tf`, and `aws/environments/dev/backend/outputs.tf`
- [x] T033 [US2] Commit the human-approved non-secret dev backend account and `us-east-1` inputs in `aws/environments/dev/backend/dev.tfvars`, retaining a clearly non-canonical reference example; operator-policy inputs remain deferred with T030
- [x] T034 [US2] Add the credential-free native-lock partial backend example for `environments/dev/foundation/terraform.tfstate` in `aws/environments/dev/foundation/dev.s3.tfbackend.example`
- [ ] T035 [US2] Document local backend bootstrap, separately reviewed state migration, lock ownership checks, and version recovery without embedding state or credentials in `aws/environments/dev/backend/README.md` — **Superseded by ops spec 004 T004 and T010:** `aws/environments/shd/state/README.md` documents the rebuilt backend; the old state was archived with checksums under T004, and the rebuilt roots started from new keys rather than a migration (T020)
- [ ] T036 [US2] Add an explicit opt-in, non-mutating two-writer lock integration check for an already provisioned test backend in `tests/integration/aws-dev-state-lock.sh` — **Superseded by ops spec 004 T010:** every rebuilt root locks through the S3-native lockfile (`use_lockfile = true`); no successor carries the opt-in two-writer lock integration check
- [x] T037 [US2] Initialize the backend root locally and commit the generated provider checksums in `aws/environments/dev/backend/.terraform.lock.hcl`
- [ ] T038 [US2] Run and fix the User Story 2 checks for `aws/modules/state-backend/`, `aws/environments/dev/backend/`, `tests/contract/aws-dev-state.sh`, and `tests/integration/aws-dev-state-lock.sh` — **Superseded by ops spec 004 T010:** `.github/workflows/iac-checks.yml` runs the rule contracts, `terraform fmt`, `validate`, and `test`, tflint, and Trivy on the `shd` roots, and its push run at `4e62041` passed for `shd`

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

- [ ] T039 [P] [US3] Add mocked `gitops_handoff` schema, fixed value, five-service map, and absent Git-owned-field assertions in `aws/environments/dev/foundation/tests/gitops_handoff.tftest.hcl` — **Superseded by ops spec 004 T016 and T021:** the GitOps handoff became a rename of GitOps desired state to the rebuilt names (microservice-app-gitops#166), guarded by gitops `tests/contract/rebuilt-resource-names.sh`, instead of a Terraform `gitops_handoff` output
- [ ] T040 [P] [US3] Add a read-only sibling-contract check for registration data, dual activation lists, derived namespace, in-cluster destinations, and known wiring/conformance/documentation gaps in `tests/contract/aws-dev-gitops-handoff.sh` — **Superseded by ops spec 004 T016:** the sibling-contract check is gitops `tests/contract/rebuilt-resource-names.sh`, which checks the overlays, Kyverno patterns, IRSA roles, and secret keys against the rebuilt names

### Implementation for User Story 3

- [ ] T041 [US3] Complete the module exports needed for bootstrap/operator access, exact IRSA consumers, ECR overlays, and future Karpenter discovery in `aws/modules/environment-foundation/outputs.tf` — **Superseded by ops spec 004 T009:** `environment-foundation` was decomposed into per-resource modules in `terraform-aws-modules`, each with its own outputs; the Karpenter discovery outputs came with ops spec 004 T030
- [ ] T042 [US3] Implement the typed non-sensitive `gitops_handoff` object with `dev`, `microtodo-dev`, `https://kubernetes.default.svc`, EKS endpoint/CA, ECR URLs, OIDC/IRSA, and discovery values in `aws/environments/dev/foundation/outputs.tf` — **Superseded by ops spec 004 T011, T016, and T021:** the `eco` roots output their resources under standard names, GitOps consumes those names (microservice-app-gitops#166), and the audited bootstrap of `lex-mts-eco-eks-main` replaced the typed handoff object
- [ ] T043 [US3] Document the output-to-registration mapping, per-cluster bootstrap boundary, digest ownership, the corrected five-root inventory, and the two remaining GitOps gaps in `aws/environments/dev/foundation/README.md` — **Superseded by ops spec 004 T021 and microservice-app-gitops spec 009 T173:** the per-cluster bootstrap boundary is `scripts/managed/bootstrap-cluster.sh` in GitOps, and the registration is reactivated there
- [ ] T044 [US3] Run and fix the User Story 3 checks for `aws/environments/dev/foundation/tests/gitops_handoff.tftest.hcl`, `tests/contract/aws-dev-gitops-handoff.sh`, and `aws/environments/dev/foundation/README.md` — **Superseded with T039-T043**

**Checkpoint**: The foundation handoff needs no Terraform-output redesign when
GitOps later resolves its own value-only wiring, conformance fixture, add-on
inventory mismatch, and central-versus-per-cluster documentation conflict.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Complete CI, cost, security, and operator documentation across all
stories without provisioning resources.

- [ ] T045 [P] Configure the dev foundation project, input examples, and three-NAT/two-node cost visibility in `infracost.yml` — **Superseded by microservice-app-gitops spec 009 T046** (microservice-app-ops#26): the Infracost job of `.github/workflows/aws-full-foundation-checks.yml` estimates every changed Terraform root under `aws/`, including the rebuilt roots, so no `infracost.yml` project file is needed
- [ ] T046 [P] Add pinned formatting, backend-free validation, mocked Terraform tests, ShellCheck, contract tests, Trivy config scanning, and Infracost validation without AWS static credentials or apply steps in `.github/workflows/aws-dev-foundation-checks.yml` — **Superseded by ai-agents specs/001 T025:** `.github/workflows/iac-checks.yml` is the backend-free gate for the rebuilt roots; the legacy `aws-dev-foundation-checks.yml` still covers only `aws/environments/dev/foundation` until the legacy roots go
- [ ] T047 [P] Add the AWS dev architecture, separate-backend boundary, four-command preview, ownership split, and links to `specs/001-aws-dev-foundation/quickstart.md` in `README.md` — **Superseded by ops spec 004:** the dev architecture it would document is retired; `README.md` still lists the legacy layout and notes the restructuring, and no task yet owns rewriting it for the rebuilt layout
- [ ] T048 Run Terraform formatting/initialization/validation/tests, ShellCheck, all `tests/contract/aws-dev-*.sh`, and Trivy against `aws/`, `scripts/aws-dev-foundation.sh`, and `.github/workflows/aws-dev-foundation-checks.yml` — **Superseded by ops spec 004 T010-T012:** the `iac-checks` gate runs formatting, validation, tests, tflint, and Trivy on every rebuilt root; T010 and T011 record its passing push runs for `shd` (`4e62041`) and `eco` (`c6d35cb`)
- [ ] T049 In an approved account with an already conforming backend, run the four-command non-mutating preview and record inventory, lock, account, cost, and zero-Azure/future-environment evidence in `specs/001-aws-dev-foundation/checklists/acceptance.md` — **Superseded by ops spec 004 T020:** the rebuilt roots were applied from reviewed saved plans in account `575172595729`, and re-plans of all twenty live roots reported no changes (`~/backups-microtodosuite/post-bringup-replan-20260914T220806Z/`)
- [ ] T050 Reconcile implemented paths and commands back into `specs/001-aws-dev-foundation/quickstart.md`, verify the known diagram/GitOps discrepancies remain explicit in `specs/001-aws-dev-foundation/research.md`, and run whitespace/diff checks across `specs/001-aws-dev-foundation/` — **Superseded by ops spec 004:** its `plan.md` target layout records the implemented paths; this specification's `quickstart.md` and `research.md` stay as the historical record of the legacy layout

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
  proposes only the expected in-place VPC CNI configuration update — **Superseded by ops spec 004 T019 and T011:** the legacy cluster this refresh plan targeted was destroyed on 2026-09-11, and the rebuilt `eco/workload` creates the VPC CNI add-on with `enableNetworkPolicy = "true"` from the start (`aws/environments/eco/workload/locals.tf:49`, asserted in `tests/workload.tftest.hcl:191`); T053's live node-agent check remains open against the rebuilt cluster
- [ ] T053 [US1] After a separately authorized apply, use read-only cluster
  inspection to confirm every ready `aws-node` pod has a ready
  `aws-eks-nodeagent` container with `--enable-network-policy=true`

---

## Phase 8: Economical New-Account Recovery

**Purpose**: Recreate only the economical shared-cluster platform in replacement
AWS account `575172595729`, preserving the previous account's state as recovery
evidence and re-entering the GitOps-only operating model after bootstrap.

- [X] T054 Record the replacement account, authorized scope, clean-state boundary,
  execution role, and GitOps handoff in the specification and implementation plan
- [X] T055 Add failing shell-contract assertions for the replacement account in
  `tests/contract/aws-dev-foundation.sh` before changing active Terraform inputs
- [X] T056 Replace the account and execution-role values in the dev backend,
  foundation, and reviewed IAM policy; run all static and mocked Terraform checks
- [X] T057 Back up the prior local state and establish the approved
  `microtodosuite-terraform-dev` assumed-role session in account `575172595729`
- [X] T058 Create the S3/KMS backend from an inspected saved plan with zero
  destroys, generate `dev.s3.tfbackend` from typed outputs, and verify no drift
- [X] T059 Create the economical dev foundation from an inspected saved plan with
  zero destroys, preserve its resulting state externally, and verify no drift
- [ ] T060 Update the sibling GitOps account-specific values from Terraform
  outputs, pass render/schema checks, merge through protected `main`, perform only
  the audited ArgoCD/root bootstrap, and verify reconciliation and service health — **Superseded by ops spec 004 T016, T021, and T022 and microservice-app-gitops spec 009 T173:** GitOps moved to the rebuilt names in microservice-app-gitops#166, `lex-mts-eco-eks-main` was bootstrapped with exactly two mutations (`~/backups-microtodosuite/eco-argocd-bootstrap-20260914T220356Z/transcript.txt`), and gitops#181 reactivated the registration; that live state is historical, since the account is now unreachable
- [X] T061 Add a failing wrapper contract proving account recovery selects the
  replacement backend with `terraform init -reconfigure`
- [X] T062 Implement the wrapper reconfiguration path and rerun its shell contract

---

## Phase 9: The Account as a Parameter

**Purpose**: Declare the AWS account once so the next account change is one
command and a passing contract, not a repository-wide search. Three accounts in
three weeks (`995253610162`, `916491575487`, `575172595729`) made this necessary.

- [X] T063 Add failing contracts in `tests/contract/aws-account-parameter.sh` and
  `tests/contract/set-aws-account.sh` requiring one declared account, rejecting any
  tracked file that carries another or a retired account, and proving a
  one-command change on a disposable copy
- [X] T064 Declare the account in `config/aws-account.env`, implement
  `scripts/set-aws-account.sh`, list every remaining foreign account with its reason
  in `config/aws-account-exceptions.txt`, make `tests/contract/aws-dev-foundation.sh`
  read the declaration, and run both contracts in `aws-dev-foundation-checks.yml`

## Phase 10: Release Authentication Repair

**Purpose**: Restore release publication after the custom GitHub token became
invalid, without introducing a long-lived repository secret.

- [X] T065 Use the repository-scoped GitHub Actions token for semantic-release
  - [X] Commit a failing contract for explicit release permissions, full history, and native token use
  - [X] Replace the invalid custom `GH_TOKEN` dependency in `.github/workflows/release.yml`
  - [X] Run the release contract in the required pull-request workflow
  - [X] Verify merged `Release` run `34612308727` publishes `v1.5.0` successfully on `main`

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
