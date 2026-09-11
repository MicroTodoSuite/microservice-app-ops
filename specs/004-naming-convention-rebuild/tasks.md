# Tasks: Naming-Convention Adoption and Infrastructure Rebuild

Traceability: each task names its artifact. Tasks marked **[approval]** need the
maintainer's approval of an exact saved plan or operation before they run.

## Phase 0: Preconditions

- [X] T001 Record the deployed inventory with current and new names in `specs/004-naming-convention-rebuild/plan.md`
- [ ] T002 Merge the constitution 4.0.0 amendment permitting an approved rebuild (maintainer)
- [ ] T003 Amend spec 009 FR-003 and user story 5 in `microservice-app-gitops` to match the constitution (maintainer approval)

## Phase 1: Preserve

- [ ] T004 Archive every object in the old state bucket and every local backup to `~/backups-microtodosuite/rebuild-<timestamp>/`, with checksums
- [ ] T005 Snapshot the four observability volumes and record the snapshot IDs
- [ ] T006 Export both log groups and the Route 53 record sets
- [ ] T007 Record the live ArgoCD revision and Application health as the pre-rebuild baseline

## Phase 2: Build (no destruction)

- [ ] T008 Add failing contracts for the naming, tag, domain, and module-source rules against the plan JSON in `tests/contract/`
- [ ] T009 Decompose `environment-foundation` into the modules of the target layout, each with the PC-IAC-001 layout, `sample/`, and `tests/`
- [ ] T010 Write the `shd` roots, with the GitHub OIDC provider and the public zone imported rather than created
- [ ] T011 Write the `eco` roots in the PC-IAC-022 domain order, consuming the account through `var.aws_account_id`
- [ ] T012 Restructure the `fdev`, `fstg`, `fprd`, and egress roots in code to the same layout
- [ ] T013 Create the new ECR repositories and copy every image, signature, and attestation by digest; verify each with Cosign **[approval]**
- [ ] T014 Create the new secrets and copy both Slack webhook values without printing them **[approval]**
- [ ] T015 Produce saved plans for every new root against empty keys and make T008 pass
- [ ] T016 On a GitOps branch, replace account-dependent values with the planned outputs; update Kyverno's repository pattern and ExternalSecret keys
- [ ] T017 Update the reusable workflow's publication guard and the five service workflows to the new repository and role names

## Phase 3: Rebuild window

- [ ] T018 Pause ArgoCD auto-sync and CI publication; remove workloads and volumes through GitOps
- [ ] T019 Destroy the `eco` foundation from a reviewed saved plan **[approval]**
- [ ] T020 Apply the new roots in order from their saved plans **[approval]**
- [ ] T021 Merge the GitOps branch and run the audited bootstrap for `gcs-mts-eco-eks-main`
- [ ] T022 Resume ArgoCD auto-sync and CI publication

## Phase 4: Validate and clean

- [ ] T023 Verify every Application Healthy and Synced and the five services' cross-service checks
- [ ] T024 Publish one image through the renamed publisher role from a service's `main`
- [ ] T025 Sweep the account for orphans and every repository for old names; record the result
- [ ] T026 Delete the old bucket, repositories, secrets, and KMS keys after the retention period; delete the default VPC **[approval]**
- [ ] T027 Activate the ops `main` ruleset requiring one approval (maintainer decision G6), once T023–T025 pass
