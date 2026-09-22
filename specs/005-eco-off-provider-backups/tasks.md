# Tasks: Off-Provider Backups for the Economical Profile

**Input**: [spec.md](spec.md) and [plan.md](plan.md)

**Companion register**: `microservice-app-gitops/specs/012-eco-velero-offsite-backups/tasks.md`
owns the ArgoCD, Velero, External Secrets, `BackupStorageLocation`, and Schedule
work. This register owns Azure storage, cross-provider state replication, AWS
identity prerequisites, and the recovery drill. Keeping one register in each
owning repository follows the cross-repository delivery rule and avoids making
the ops repository authoritative for GitOps desired state.

**Tests**: Contract tasks precede every implementation task. A contract is
committed while red and is marked complete only after its named artifact and
observed failing run have both been inspected.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: The task can run in parallel because it changes different files and
  has no dependency on incomplete work.
- **[US1]**, **[US2]**, and **[US3]** map to the user stories in [spec.md](spec.md).

## Phase 1: Specification and decisions

**Purpose**: Make the recovery boundary reviewable before any implementation.

- [X] T001 Record option A, the recovery objectives, the cross-repository ownership boundary, and the implementation sequence in `specs/005-eco-off-provider-backups/spec.md`, `specs/005-eco-off-provider-backups/plan.md`, and `specs/005-eco-off-provider-backups/tasks.md`
- [ ] T002 Obtain the maintainer's decisions D1-D5 from `specs/005-eco-off-provider-backups/spec.md` and encode the selected values before any Azure or Velero implementation changes
- [ ] T003 Run the read-only Azure for Students preflight for app-registration authority, provider registration, storage availability, and regional constraints, then record redacted evidence in `docs/evidence/eco-off-provider-backups/preflight.json`

---

## Phase 2: Foundational Azure module and state prerequisites

**Purpose**: Satisfy MTS-IAC-102 before a live root consumes reusable Azure
resources. These tasks belong to future `terraform-azure-modules` pull requests;
they are dependencies, not a third pull request in the current authoring stage.

**CRITICAL**: T014 and T015 MUST NOT start until T002-T010 are complete and the
released module tags exist. Their red contracts T011-T013 intentionally precede
those dependencies.

- [ ] T004 [P] Create and release the resource-group module in `terraform-azure-modules/resource-group/`
- [ ] T005 [P] Create and release the storage-account module, including private containers and hardening outputs, in `terraform-azure-modules/storage-account/`
- [ ] T006 [P] Create and release the managed-identity module, including federated credentials, in `terraform-azure-modules/managed-identity/`
- [ ] T007 [P] Create and release the role-assignment module with container-scoped assignments in `terraform-azure-modules/role-assignment/`
- [ ] T008 Create the AzureRM backend bootstrap root and externally backed-up local-state receipt in `azure/environments/shd/state/`
- [ ] T009 Publish exact independent module tags and record them in `specs/005-eco-off-provider-backups/plan.md`
- [ ] T010 Confirm the Azure backend choice from D2 and record its unique state keys in `azure/environments/shd/state/README.md`

**Checkpoint**: The Azure modules have reviewed releases and the live roots can
store their own state outside the AWS account.

---

## Phase 3: User Story 1 - Replicate Terraform state outside AWS (Priority: P1)

**Goal**: Copy every `eco/` and `shd/` Terraform state object to hardened Azure
Blob storage through OIDC and retain verifiable versions.

**Independent Test**: The root tests plan offline with a mock provider, the
source contract validates the root boundary, and the workflow contract rejects
any non-OIDC or destructive copy path.

### Red contracts

- [X] T011 [P] [US1] Add failing mock-provider, plan-only contracts for the workload and security roots in `azure/environments/eco/workload/tests/workload.tftest.hcl` and `azure/environments/eco/security/tests/security.tftest.hcl`
- [X] T012 [P] [US1] Add a failing source contract for module pins, backend/provider policy, private containers, storage hardening, and credential absence in `tests/contract/azure-eco-backups.sh`
- [X] T013 [P] [US1] Add a failing workflow contract for schedule, OIDC, prefix coverage, manifest integrity, and non-destructive behavior in `tests/workflows/eco-state-replication.bats`

**Red evidence (2026-09-22)**:

- `terraform -chdir=azure/environments/eco/workload test -no-color` exits 1
  before a plan because the unimplemented root declares no AzureRM provider:
  `Error: unknown provider registry.terraform.io/hashicorp/azurerm`.
- `terraform -chdir=azure/environments/eco/security test -no-color` exits 1
  for the same missing-root condition. Both files contain only `command = plan`
  runs against `mock_provider "azurerm"`; neither initializes a backend.
- `./tests/contract/azure-eco-backups.sh` exits 1 with
  `FAIL: 12 economical Azure backup contract violation(s)`.
- `./tests/workflows/eco-state-replication.bats` exits 1 with
  `FAIL: 25 state-replication workflow contract violation(s)`.

### Implementation

- [ ] T014 [P] [US1] Implement the resource group, storage account, and two private containers through exact released module tags in `azure/environments/eco/workload/`
- [ ] T015 [P] [US1] Implement the replication identity, federated credential, and container-scoped role assignments in `azure/environments/eco/security/`
- [ ] T016 [P] [US1] Add the least-privilege GitHub OIDC state-reader role to `aws/environments/shd/security/`
- [ ] T017 [US1] Implement the six-hour and manual state-copy job with integrity manifests in `.github/workflows/eco-state-replication.yml`
- [ ] T018 [US1] Turn T011-T013 green without weakening their assertions and record the decisive output in `specs/005-eco-off-provider-backups/tasks.md`
- [ ] T019 [US1] Confirm from saved plan JSON that the changed AWS roots add only the approved identity resources and that the economical runtime roots have no unrelated changes; retain the summaries in `docs/evidence/eco-off-provider-backups/plans/`
- [ ] T020 [US1] Dispatch the replication workflow, compare every source and destination SHA-256, and record the run URL plus redacted manifest evidence in `docs/evidence/eco-off-provider-backups/state-replication.md`

**Checkpoint**: A verified copy of every in-scope state object exists outside
AWS, and no static cloud credential or delete path exists.

---

## Phase 4: User Story 2 - Back up the economical cluster (Priority: P1)

**Goal**: Provide only the AWS-side secret and identity prerequisites that the
companion GitOps feature consumes. GitOps spec 012 owns all cluster desired
state and its tests.

**Independent Test**: The AWS Terraform tests prove the empty secret container
and namespace-scoped IRSA reader; the companion GitOps contracts prove that no
credential value enters Git and that Velero targets only `velero-eco`.

- [ ] T021 [P] [US2] Add a failing contract for the empty Velero credential secret container in `aws/environments/eco/security/tests/security.tftest.hcl`
- [ ] T022 [P] [US2] Add a failing contract for the External Secrets reader IRSA role in `aws/environments/eco/security-irsa/tests/security-irsa.tftest.hcl`
- [ ] T023 [US2] Implement the empty secret container `lex-mts-eco-sm-velero` in `aws/environments/eco/security/`
- [ ] T024 [US2] Implement the namespace-scoped secret-reader role `lex-mts-eco-role-velerosec` in `aws/environments/eco/security-irsa/`
- [ ] T025 [US2] Turn T021-T022 green without weakening their assertions and record the decisive output in `specs/005-eco-off-provider-backups/tasks.md`
- [ ] T026 [US2] Verify the completed companion tasks in `microservice-app-gitops/specs/012-eco-velero-offsite-backups/tasks.md` against their named manifests and retained evidence

**Checkpoint**: ArgoCD can reconcile the companion feature without any secret
value in Git and Velero can write only to its container.

---

## Phase 5: User Story 3 - Prove recovery from the copies (Priority: P2)

**Goal**: Rebuild `eco` from the off-provider copies and measure real recovery
time and recovery point age.

**Independent Test**: A drill starts with the AWS account unavailable, verifies
the replicated state manifest, rebuilds from reviewed saved plans, restores the
latest successful Velero backup, and records measured RTO and RPO.

- [ ] T027 [P] [US3] Write the state-reconstruction and Velero restore drill with required evidence fields in `docs/eco-off-provider-recovery.md`
- [ ] T028 [P] [US3] Add a failing lifecycle contract for recording the latest successful Velero backup beside every economical down bundle in `tests/contract/aws-profile-lifecycle.sh`
- [ ] T029 [US3] Implement the non-mutating backup-record capture in `scripts/aws-profile-lifecycle.sh` and turn T028 green
- [ ] T030 [US3] Execute an approved recovery drill from Azure copies alone and record measured RTO, measured RPO, data-loss disclosures, and pass or miss status in `docs/evidence/eco-off-provider-drill-<date>.md`

**Checkpoint**: The platform has observed recovery evidence; no target is
reported as met solely because the backup configuration exists.

---

## Phase 6: Cross-cutting verification

- [ ] T031 [P] Re-run the mandatory IaC, workflow, formatting, lint, and security gates and quote the decisive results in the implementing pull requests
- [ ] T032 [P] Review the Azure for Students cost estimate and record the accepted monthly ceiling in `docs/evidence/eco-off-provider-backups/cost.md`
- [ ] T033 Verify that the final ops and GitOps pull requests name each other and that every completed task is marked only against an inspected artifact

---

## Dependencies and execution order

- T001 is the approved specification baseline; T002 and T003 gate all creation.
- T004-T007 can proceed in parallel, then T009 publishes the exact tags.
- T008 and T010 establish the Azure state boundary before T014 or T015.
- T011-T013 are the red SDD contracts and precede T014-T017.
- T014 precedes T015 because the role-assignment scopes are container IDs.
- T016 and T017 can proceed after T011-T013; T020 waits for T014-T019.
- T021-T022 precede T023-T024. Companion GitOps spec 012 can proceed in
  parallel after D1 and D5 are decided, but T026 waits for both repositories.
- T027-T029 can proceed after the backup paths exist. T030 waits for all P1
  tasks and requires a separate approved drill window.
- T031-T033 close the feature only after the desired implementation increment.

## Parallel examples

```text
T004 resource-group module | T005 storage module | T006 identity module | T007 role-assignment module
T011 Terraform red tests | T012 source red contract | T013 workflow red contract
T021 secret-container red test | T022 IRSA red test | companion GitOps red contracts
```

## Implementation strategy

1. Review and merge the specification plus deliberately failing contracts.
2. Decide D1-D5 and deliver the module/backend prerequisites.
3. Complete US1 first so the platform state survives an AWS-account loss.
4. Complete US2 through paired ops and GitOps pull requests.
5. Complete US3 only through an approved real drill; a document or green render
   is not recovery evidence.

The minimum useful increment is US1. It establishes an independently verifiable
off-provider copy before cluster backup and recovery automation are added.
