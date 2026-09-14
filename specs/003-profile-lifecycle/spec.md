# Feature Specification: Profile-Aware AWS Runtime Lifecycle

**Feature Branch**: `feat/profile-lifecycle`

**Created**: 2026-09-10

**Status**: In Progress

**Input**: Keep durable AWS data and release assets while making the economical and full runtime profiles quick to start and stop through reviewed Terraform saved plans.

## Clarifications

### Session 2026-09-10

- **Q**: Which resources survive a profile shutdown?
  **A**: Remote state, ECR repositories and images, Secrets Manager containers and values, Route 53 hosted zones and records, and account-level GitHub publication identities remain managed and present. VPC, NAT, EKS, managed nodes, cluster add-ons, and cluster-scoped identities are runtime resources.
- **Q**: Does shutdown use an unrestricted `terraform destroy` on a foundation root?
  **A**: No. Foundation roots mix durable and runtime resources. Shutdown plans the same root with `runtime_enabled=false`; this preserves the durable addresses while removing the runtime graph.
- **Q**: Which roots form each operator profile?
  **A**: `economical` maps to `aws/environments/dev/foundation`. `full` maps to `aws/shared/egress`, `aws/environments/full-dev/foundation`, `aws/environments/demo-full/foundation`, and `aws/environments/full-prod/foundation`. *Superseded on 2026-09-13 for the rebuilt roots; see that session.*
- **Q**: May the wrapper apply an unsaved or unreviewed plan?
  **A**: No. Planning and applying are separate commands. Apply accepts only a saved plan bundle created by the wrapper and refuses a mismatched profile or direction.
- **Q**: Does the wrapper mutate a GitOps-managed cluster directly?
  **A**: No. A down plan requires an explicit GitOps quiescence revision supplied by the operator. Workload deactivation and persistent-data disposition must first be merged in `microservice-app-gitops` and reconciled by ArgoCD.
- **Q**: Is the full profile ready to apply in the replacement AWS account as part of this feature?
  **A**: No. The wrapper exposes and validates the full profile, but it must stop if any root still targets another account or lacks its local backend/input configuration. Migrating and accepting the full-profile roots remains separate work under spec 009.

### Session 2026-09-11

- **Q**: Should operators invoke the lifecycle script directly for routine work?
  **A**: No. A repository-root Makefile is the primary operator interface. It delegates every operation to the existing wrapper so profile validation, durable-resource guards, saved-plan provenance, and GitOps quiescence requirements remain centralized.
- **Q**: May one Make target plan and apply an up or down transition automatically?
  **A**: No. Make keeps planning, inspection, and applying as separate targets. Profile-sensitive targets require an explicit `PROFILE=economical|full`; apply targets require an explicit saved-plan `BUNDLE`, and down planning requires `GITOPS_REVISION`.
- **Q**: How is PersistentVolume data protected when a profile goes down?
  **A**: GitOps quiescence prunes PersistentVolumeClaims. With the `Delete` reclaim policy, the EBS CSI driver then deletes their volumes before any Terraform plan runs; the 2026-09-11 teardown lost four observability volumes that way. The wrapper therefore snapshots every EBS CSI volume through the EC2 API before quiescence, and records a snapshot or explicit consent per volume. A down plan requires that record (maintainer decision, 2026-09-13; ai-agents specs/001 T038).

### Session 2026-09-13 (rebuilt roots)

Decided under the maintainer's delegation of pending decisions; ai-agents specs/001 T027.

- **Q**: Which roots does each profile operate after the naming rebuild?
  **A**: `economical` operates `aws/environments/eco/networking`, `aws/environments/eco/workload`, and `aws/environments/eco/security-irsa`. `shd/state`, `shd/security`, `shd/registry`, `shd/dns`, and `eco/security` hold the persistent resources and are never planned. `full` will operate `shd/networking` and the `fdev`, `fstg`, and `fprd` roots once ops spec 004 T012 writes them; until then it is refused. The legacy roots of the 2026-09-10 session are no longer planned; release `v1.17.0` is the last that maps them.
- **Q**: How does a rebuilt environment go down without destroying persistent resources?
  **A**: The IRSA pass and the cluster roots hold only runtime resources, so down destroys them. `eco/networking` is planned with `nat_gateways_enabled=false`, which removes only the NAT gateways, their Elastic IPs, and the private default routes. Its VPC stays, because `eco/security`'s security groups belong to it.
- **Q**: How does a down transition delete a cluster whose deletion protection is on?
  **A**: Amazon EKS refuses to delete a protected cluster. While the cluster in `eco/workload`'s state is protected, the down bundle holds only a plan that turns the protection off. The operator applies it and plans down again for the destroy bundle. One bundle cannot hold both, because applying the first plan changes the state the destroy plan was saved against.
- **Q**: Why can an up transition take two bundles?
  **A**: The IRSA pass reads the cluster's OIDC issuer, so it cannot be planned while no cluster exists. Without a cluster, the up bundle holds `eco/networking` and `eco/workload`; the next up bundle adds the IRSA pass.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stop economical runtime spend without deleting durable assets (Priority: P1)

A platform operator can create and review a saved shutdown plan for the economical profile that removes its VPC, NAT gateways, EKS cluster, nodes, add-ons, and cluster-scoped identities while retaining state, images, secrets, and DNS.

**Independent Test**: Plan the dev foundation with runtime disabled, inspect the plan JSON, and verify that every deletion belongs to the documented runtime allowlist while durable addresses are no-op. Since 2026-09-13: plan `economical down` against the eco roots and verify that only `eco/security-irsa` and `eco/workload` are destroyed and that `eco/networking` deletes only its NAT egress.

**Acceptance Scenarios**:

1. **Given** the economical runtime is active and GitOps is quiesced, **When** an operator plans `economical down`, **Then** the wrapper saves a reviewable plan and never applies it implicitly.
2. **Given** the saved shutdown plan, **When** its JSON is audited, **Then** no ECR repository, Secrets Manager secret, Route 53 zone or record, state backend, or GitHub publication identity is deleted.
3. **Given** a saved plan for another profile or direction, **When** an operator asks the wrapper to apply it, **Then** the wrapper refuses the mismatch.

### User Story 2 - Restore the economical runtime from durable state (Priority: P1)

A platform operator can generate a saved start plan for the economical profile and apply that exact reviewed artifact so Terraform recreates the runtime around the preserved durable resources.

**Acceptance Scenarios**:

1. **Given** the economical runtime is disabled, **When** an operator plans `economical up`, **Then** runtime resources are recreated and durable resources remain no-op.
2. **Given** a reviewed saved start plan, **When** it is applied, **Then** only the exact saved plan is used.
3. **Given** an expired AWS login or unexpected account, **When** any planning command starts, **Then** it stops before Terraform changes state.

### User Story 3 - Operate the full profile with dependency-safe ordering (Priority: P2)

A platform operator can use the same interface for the expensive full profile while preserving the ordering between the shared egress hub and its three environment foundations. *Deferred on 2026-09-13 until ops spec 004 T012 writes the rebuilt full roots (FR-026).*

**Acceptance Scenarios**:

1. **Given** all full-profile inputs target the active account, **When** planning an up transition, **Then** the egress hub is planned before the three foundations.
2. **Given** the full profile is active and quiesced, **When** planning a down transition, **Then** all foundations are planned with runtime disabled before the egress hub is planned for destruction.
3. **Given** any full root is still configured for a retired account or lacks required local configuration, **When** the profile preflight runs, **Then** it stops with the exact root and remediation requirement.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The foundation module MUST expose `runtime_enabled`, defaulting to `true` so an ordinary plan preserves the current topology.
- **FR-002**: `runtime_enabled=false` MUST remove the VPC, NAT gateways, EKS cluster, managed nodes, EKS add-ons, flow-log resources, Karpenter runtime resources, and cluster-scoped IAM/IRSA resources.
- **FR-003**: Runtime disablement MUST preserve remote state, ECR, Secrets Manager, Route 53, GitHub OIDC publication resources, and their Terraform ownership.
- **FR-004**: Existing singleton runtime addresses MUST use explicit Terraform `moved` blocks when adding conditional instances, so the first enabled plan does not replace resources solely because of the feature.
- **FR-005**: Every foundation root MUST pass a root-level `runtime_enabled` input to the shared module and default it to `true`.
- **FR-006**: The wrapper MUST support the exact profile names `economical` and `full`, and the exact directions `up` and `down`.
- **FR-007**: The wrapper MUST separate preflight, initialization, saved-plan creation, inspection, and saved-plan apply; it MUST NOT expose an auto-approve path.
- **FR-008**: A down plan MUST require a non-empty GitOps revision acknowledgement and record it beside the plan artifact.
- **FR-009**: Every command that reads or mutates remote state MUST verify AWS STS account identity against each root's effective `expected_account_id` before invoking Terraform.
- **FR-010**: The full profile MUST start the egress root before its environment roots and stop environment runtimes before destroying egress.
- **FR-011**: The wrapper MUST reject incomplete local backend or variable inputs rather than guessing account IDs, CIDRs, policy ARNs, operator addresses, or transit-gateway IDs.
- **FR-012**: The wrapper MUST never invoke `kubectl`, edit the GitOps repository, or claim ArgoCD reconciliation.
- **FR-013**: The wrapper MUST store plans and metadata in a gitignored local directory and verify profile, direction, account, commit, and plan-file checksums before apply.
- **FR-014**: Documentation MUST distinguish the residual cost of durable services from the removed runtime cost and MUST warn about persistent-volume data before shutdown.
- **FR-015**: The repository-root Makefile MUST expose `check`, `init`, `status`, `plan-up`, `plan-down`, `inspect`, `apply-up`, and `apply-down` as the primary operator targets.
- **FR-016**: Make targets MUST delegate to the lifecycle wrapper and MUST NOT invoke Terraform, kubectl, plan-and-apply sequences, or auto-approval directly.
- **FR-018**: The wrapper MUST provide `snapshot-volumes {economical|full}`. It finds every EBS volume in the profile's region that carries the `ebs.csi.aws.com/cluster` or `CSIVolumeName` tag, through the EC2 API, and snapshots each volume that `--consent` does not name. It waits for the snapshots to complete, then writes a checksummed record: the profile, account, region, and creation time, and each volume's snapshot ID or consent.
- **FR-019**: A down plan MUST require `--volume-record`. It MUST reject a record whose checksum, profile, account, or region does not match; one created after the GitOps quiescence commit; one that omits an EBS CSI volume still present; and one whose snapshots are not completed. It MUST copy the record into the checksummed bundle, and an apply-down MUST require it there.
- **FR-020**: The Makefile MUST expose `snapshot-volumes` with an optional `CONSENT` list of volume IDs, and `plan-down` MUST require `VOLUME_RECORD`.
- **FR-017**: Profile-sensitive Make targets MUST require an explicit `PROFILE` equal to `economical` or `full`; inspection and apply targets MUST require `BUNDLE`, and down planning MUST require `GITOPS_REVISION`.

FR-001 to FR-005, FR-009, and FR-010 describe the legacy foundation and egress roots. Since 2026-09-13 the wrapper plans the rebuilt roots under FR-021 to FR-026 instead.

- **FR-021**: The `economical` profile MUST plan exactly `aws/environments/eco/networking`, `aws/environments/eco/workload`, and `aws/environments/eco/security-irsa`, in that order up and in reverse down. It MUST NOT plan `shd/state`, `shd/security`, `shd/registry`, `shd/dns`, or `eco/security`.
- **FR-022**: A down plan MUST destroy `eco/security-irsa` and `eco/workload` and plan `eco/networking` with `nat_gateways_enabled=false`. An up plan MUST plan `eco/networking` with `nat_gateways_enabled=true`. While `eco/workload`'s state holds no cluster, the up plan MUST leave out `eco/security-irsa` and tell the operator to plan up again.
- **FR-023**: `eco/networking` MUST expose `nat_gateways_enabled`, defaulting to `true`; `false` MUST remove only the NAT gateways, their Elastic IPs, and the private NAT routes. The wrapper MUST reject a networking down plan that deletes any other address.
- **FR-024**: `eco/workload` MUST expose `cluster_deletion_protection`, defaulting to `true`. While the cluster in its state is protected, a down plan MUST hold only an `eco/workload` plan with `cluster_deletion_protection=false`, MUST reject that plan if it deletes anything, and MUST tell the operator to plan down again.
- **FR-025**: Every command that reads or mutates remote state MUST verify that AWS STS, `AWS_ACCOUNT_ID` in `config/aws-account.env`, and each root's literal `aws_account_id` name one account, and that the profile's roots name one literal `aws_region`.
- **FR-026**: Until the rebuilt full-profile roots exist (ops spec 004 T012), every `full` command that reads state MUST stop and name that task.

## Success Criteria *(mandatory)*

- **SC-001**: Contract tests demonstrate that the default runtime setting leaves all four foundation roots enabled.
- **SC-002**: Terraform tests demonstrate that disabling a foundation yields null or empty runtime outputs while durable output maps remain present.
- **SC-003**: A wrapper-created plan bundle can be inspected and applied only when its metadata matches the requested profile, direction, account, Git commit, and checksums.
- **SC-004**: An economical shutdown plan contains no delete action for the documented durable resource classes.
- **SC-005**: The full-profile preflight reports its current replacement-account readiness without applying or destroying infrastructure.
- **SC-006**: Contract tests demonstrate the exact Make-to-wrapper command mapping for both profiles and prove that missing or invalid safety inputs stop before the wrapper runs.
- **SC-007**: Contract tests demonstrate the economical up and down bundles for each state of the cluster (absent, protected, and unprotected), reject a networking down plan that deletes more than the NAT egress, and reject a root whose account differs from the declared one. SC-001 and SC-002 apply to the legacy foundation roots only.

## Out of Scope

- Mapping the full profile before ops spec 004 T012 writes its rebuilt roots.

- Automatically committing GitOps activation or quiescence changes.
- Migrating the inactive full-profile roots from a retired account.
- Applying either profile during implementation of this feature.
- Backing up application-level persistent volumes or databases.
- Removing the lifecycle wrapper or adding a one-command plan-and-apply shortcut.
