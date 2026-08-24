# Feature Specification: AWS Full-Profile Demonstration Foundation

**Feature Branch**: `agent/full-profile-demo`

**Created**: 2026-08-22

**Status**: Draft

**Input**: Provision a second, independent AWS environment demonstrating the full/expensive architecture profile -- a dedicated VPC and EKS cluster, not sharing infrastructure with the existing economical dev cluster (which hosts dev/staging/production as namespaces). Reuse the existing foundation module without modification.

## Clarifications

### Session 2026-08-22

- **Q**: What is the name of this environment to avoid colliding with `dev`, `staging`, and `prod`?
  **A**: It will be named `demo-full` to explicitly denote its purpose as a full-profile demonstration, avoiding any conflict with the logical namespaces used in the economical cluster.
- **Q**: What is the network CIDR for this environment?
  **A**: As requested, it uses the already-reserved `10.20.0.0/16`.
- **Q**: Do we modify the foundation module?
  **A**: No, we reuse the existing foundation module in `aws/modules/environment-foundation` without modification.
- **Q**: What are the profile-specific parameters?
  **A**: Node capacity mix (e.g., using On-Demand capacity rather than Spot) reflects the full/expensive architecture.
- **Q**: What state-locking pattern is used?
  **A**: The same remote S3/lockfile pattern already established for `dev`, but isolated via a distinct S3 prefix and locking key for `demo-full`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preview the full-profile demonstration environment (Priority: P1)

As a platform engineer, I can provide the documented demonstration inputs and preview the complete AWS foundation from the repository root without duplicating the foundation module logic.

**Independent Test**: From `aws/environments/demo-full/foundation`, follow the documented init and plan commands. The plan shows a dedicated VPC (10.20.0.0/16) and EKS cluster, with no mutations to the existing `dev` environment.

**Acceptance Scenarios**:
1. **Given** valid inputs and backend, **When** planning the foundation, **Then** the plan contains a new VPC, EKS cluster, and required IAM roles.
2. **Given** the existing `dev` environment, **When** the demo foundation is planned, **Then** the plan contains only the new AWS `demo-full` scope and does not mutate `dev` resources.

### User Story 2 - Share protected, isolated state (Priority: P2)

As a platform team member, I can collaborate on the demonstration foundation through remote, recoverable state whose lock prevents concurrent writers and whose address cannot collide with the `dev` state.

**Acceptance Scenarios**:
1. **Given** two authorized operators target the `demo-full` state concurrently, **When** one holds the lock, **Then** the second stops without writing state.
2. **Given** the `dev` state exists, **When** `demo-full` reads or writes state, **Then** it uses a completely isolated path.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The foundation MUST target exactly one environment named `demo-full`.
- **FR-002**: The network MUST use CIDR `10.20.0.0/16`.
- **FR-003**: The foundation module from `aws/modules/environment-foundation` MUST be reused without modification.
- **FR-004**: The environment MUST use full-profile node capacity (e.g. On-Demand instances).
- **FR-005**: State MUST be stored remotely and isolated from `dev` using the identical locking mechanism.
- **FR-006**: This phase provisions only the AWS infrastructure shell; registering it in GitOps and bootstrapping ArgoCD are explicitly excluded.
- **FR-007**: A teammate MUST be able to run the identical small set of documented commands already used for the dev foundation to plan the new environment.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A plan can be generated for `demo-full` using `10.20.0.0/16` and the existing foundation module.
- **SC-002**: Zero changes are made to `aws/modules/environment-foundation`.
- **SC-003**: State backend is configured independently of `dev`.
- **SC-004**: Zero GitOps registration or platform add-on deployment is attempted during infrastructure provisioning.
