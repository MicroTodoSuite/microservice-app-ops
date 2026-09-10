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
  **A**: `economical` maps to `aws/environments/dev/foundation`. `full` maps to `aws/shared/egress`, `aws/environments/full-dev/foundation`, `aws/environments/demo-full/foundation`, and `aws/environments/full-prod/foundation`.
- **Q**: May the wrapper apply an unsaved or unreviewed plan?
  **A**: No. Planning and applying are separate commands. Apply accepts only a saved plan bundle created by the wrapper and refuses a mismatched profile or direction.
- **Q**: Does the wrapper mutate a GitOps-managed cluster directly?
  **A**: No. A down plan requires an explicit GitOps quiescence revision supplied by the operator. Workload deactivation and persistent-data disposition must first be merged in `microservice-app-gitops` and reconciled by ArgoCD.
- **Q**: Is the full profile ready to apply in the replacement AWS account as part of this feature?
  **A**: No. The wrapper exposes and validates the full profile, but it must stop if any root still targets another account or lacks its local backend/input configuration. Migrating and accepting the full-profile roots remains separate work under spec 009.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Stop economical runtime spend without deleting durable assets (Priority: P1)

As a platform operator, I can create and review a saved shutdown plan for the economical profile that removes its VPC, NAT gateways, EKS cluster, nodes, add-ons, and cluster-scoped identities while retaining state, images, secrets, and DNS.

**Independent Test**: Plan the dev foundation with runtime disabled, inspect the plan JSON, and verify that every deletion belongs to the documented runtime allowlist while durable addresses are no-op.

**Acceptance Scenarios**:

1. **Given** the economical runtime is active and GitOps is quiesced, **When** an operator plans `economical down`, **Then** the wrapper saves a reviewable plan and never applies it implicitly.
2. **Given** the saved shutdown plan, **When** its JSON is audited, **Then** no ECR repository, Secrets Manager secret, Route 53 zone or record, state backend, or GitHub publication identity is deleted.
3. **Given** a saved plan for another profile or direction, **When** an operator asks the wrapper to apply it, **Then** the wrapper refuses the mismatch.

### User Story 2 - Restore the economical runtime from durable state (Priority: P1)

As a platform operator, I can generate a saved start plan for the economical profile and apply that exact reviewed artifact so Terraform recreates the runtime around the preserved durable resources.

**Acceptance Scenarios**:

1. **Given** the economical runtime is disabled, **When** an operator plans `economical up`, **Then** runtime resources are recreated and durable resources remain no-op.
2. **Given** a reviewed saved start plan, **When** it is applied, **Then** only the exact saved plan is used.
3. **Given** an expired AWS login or unexpected account, **When** any planning command starts, **Then** it stops before Terraform changes state.

### User Story 3 - Operate the full profile with dependency-safe ordering (Priority: P2)

As a platform operator, I can use the same interface for the expensive full profile while preserving the ordering between the shared egress hub and its three environment foundations.

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

## Success Criteria *(mandatory)*

- **SC-001**: Contract tests demonstrate that the default runtime setting leaves all four foundation roots enabled.
- **SC-002**: Terraform tests demonstrate that disabling a foundation yields null or empty runtime outputs while durable output maps remain present.
- **SC-003**: A wrapper-created plan bundle can be inspected and applied only when its metadata matches the requested profile, direction, account, Git commit, and checksums.
- **SC-004**: An economical shutdown plan contains no delete action for the documented durable resource classes.
- **SC-005**: The full-profile preflight reports its current replacement-account readiness without applying or destroying infrastructure.

## Out of Scope

- Automatically committing GitOps activation or quiescence changes.
- Migrating the inactive full-profile roots from a retired account.
- Applying either profile during implementation of this feature.
- Backing up application-level persistent volumes or databases.
