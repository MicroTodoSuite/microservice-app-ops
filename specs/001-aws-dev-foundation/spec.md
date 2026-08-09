# Feature Specification: AWS Dev Foundation

**Feature Branch**: `esteban/eks-dev-foundation`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Provision the foundational AWS infrastructure for one isolated development-tier environment in a single AWS account, including its network, managed Kubernetes cluster, container registry, workload identity foundation, and isolated remotely locked team state. Make the creation plan accessible through a small documented command sequence. Staging, production, and Azure AKS disaster recovery are separate future features."

## Clarifications

### Session 2026-08-09

- Q: Which approved deployment profile governs this dev foundation? → A: The ratified full profile: one dedicated dev VPC and one dedicated dev EKS cluster.
- Q: Which Kubernetes minor version will the dev EKS cluster use? → A: Kubernetes 1.35, the newest EKS standard-support version inside the KEDA 2.20 and Kyverno 1.18 tested range; 1.36 is not selected.
- Q: Which state-locking mechanism will protect the dev foundation? → A: Terraform's native S3 lockfile, not the diagrams' deprecated DynamoDB locking mechanism.
- Q: How will this foundation connect to the validated GitOps registration? → A: It will output only infrastructure-derived dev values for a later `clusters/eks-dev` sibling. The raw EKS endpoint is for operator access and the one-time ArgoCD bootstrap; the currently implemented per-cluster ArgoCD topology activates applications with `server: https://kubernetes.default.svc`. GitOps continues to own and must finish its reusable replacement wiring and future-EKS conformance fixture.
- Q: Is Karpenter part of this first dev foundation? → A: No. A managed node group supplies bootstrap capacity, while network and identity boundaries preserve a later GitOps-managed Karpenter adoption seam.
- Q: Which concrete AWS location and network values define dev? → A: Account `995253610162` in `us-east-1`, using `us-east-1a`, `us-east-1b`, and `us-east-1c`; dev reserves `10.10.0.0/16`, with `10.20.0.0/16` and `10.30.0.0/16` reserved for later staging and production specs.
- Q: How is the dev EKS public API exposed for a team with dynamic source IPs? → A: Dev intentionally uses `0.0.0.0/0`; IAM authentication and exact EKS access entries enforce access. This is a human-approved dev-only tradeoff that MUST NOT be silently narrowed or copied to staging/production, which require restricted network policies.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Preview an isolated dev foundation (Priority: P1)

As a platform engineer, I can provide the documented development inputs and
preview the complete AWS foundation from the repository root without learning
the internal module layout or changing an existing Azure infrastructure root.

**Why this priority**: A complete, reviewable plan is the first safe delivery
increment. It exposes cost, security, and topology decisions before any cloud
resource is changed.

**Independent Test**: From a clean checkout with authorized, short-lived AWS
credentials and an initialized state backend, follow the quickstart. The plan
completes through the documented entry point and contains one dev network, one
dev EKS cluster with initial worker capacity, the required ECR repositories,
and the IAM/OIDC foundation without proposing staging, production, or Azure
resources.

**Acceptance Scenarios**:

1. **Given** valid dev inputs and access to the remote state backend, **When** a teammate follows the documented preview workflow, **Then** they obtain a complete plan in no more than four commands without entering an internal module directory.
2. **Given** the existing Azure roots remain in the repository, **When** the dev foundation is planned, **Then** the plan contains only the new AWS dev scope and does not replace, import, or mutate Azure resources.
3. **Given** no prior dev foundation exists, **When** the plan is reviewed, **Then** every required network, cluster, registry, identity, and state integration component is visible with environment and ownership labels.

---

### User Story 2 - Share protected, isolated state (Priority: P2)

As a platform team member, I can collaborate on the dev foundation through
remote, recoverable state whose lock prevents concurrent writers and whose
address cannot collide with future staging or production state.

**Why this priority**: Team planning and later provisioning are unsafe if state
can be overwritten, corrupted, read publicly, or confused with another
environment.

**Independent Test**: Inspect and exercise the backend contract in an authorized
test account. The dev state has a unique environment address, encryption,
version recovery, blocked public access, and an effective lock; a second writer
cannot acquire the same state while the first holds it.

**Acceptance Scenarios**:

1. **Given** two authorized operators target the dev state concurrently, **When** one operation holds the lock, **Then** the second operation stops without writing state.
2. **Given** a future staging or production foundation follows the same structure, **When** its backend address is generated, **Then** it cannot read, lock, or overwrite the dev state object.
3. **Given** accidental state-object replacement or deletion, **When** an authorized operator follows the recovery procedure, **Then** an earlier state version can be identified and restored without exposing credentials.

---

### User Story 3 - Hand off cleanly to GitOps (Priority: P3)

As a GitOps platform maintainer, I can use the dev foundation outputs to prepare
a future value-only `clusters/eks-dev` registration without changing the
shared cluster mechanism or provider-neutral platform add-on folders.

**Why this priority**: The already validated GitOps registration is the delivery
seam for workloads and platform controllers. Infrastructure that cannot supply
its values would force a redesign before the cluster could be used.

**Independent Test**: Compare the foundation handoff contract with
`microservice-app-gitops/clusters/base` and the existing `clusters/local-kind`
registration. The handoff supplies the dev cluster endpoint, environment,
namespace, and ECR locations needed by a sibling registration and overlays;
Git source URL and revision remain reviewed GitOps values, and no shared
ApplicationSet or `infrastructure/*` root needs modification.

**Acceptance Scenarios**:

1. **Given** the dev foundation outputs, **When** a later GitOps change creates a sibling `clusters/eks-dev` directory that consumes `../base`, **Then** its `cluster-registration` values and dev activation patches can be completed without changing `clusters/base`.
2. **Given** the shared platform add-ons remain provider-neutral, **When** AWS-specific identity, secret-store, issuer, or registry bindings are added later, **Then** they can remain registration- or environment-owned and no add-on installation folder is copied or edited.
3. **Given** an image has been promoted to ECR, **When** its GitOps overlay is prepared later, **Then** the overlay can select the exact OCI digest; matching tags alone are never treated as promotion evidence.

### Edge Cases

- The selected VPC address range overlaps a network reserved for a later
  environment or an existing network in the account.
- The selected region cannot provide the required number of distinct
  availability zones or the selected EKS minor version.
- The remote state bucket or lock resource is missing, unreachable, or belongs
  to a different AWS account than the dev foundation.
- A stale lock remains after an interrupted operation; recovery must preserve an
  audit trail and must not delete an active operator's lock.
- A repeated plan with unchanged inputs proposes infrastructure changes.
- An ECR repository already exists under the required name but is not managed by
  this state.
- The cluster endpoint is created but the planned initial worker capacity cannot
  join, leaving no place for ArgoCD and the validated platform add-ons to run.
- A workload identity request omits the exact Kubernetes namespace, service
  account, or approved AWS permissions and would otherwise create broad access.
- A future GitOps registration tries to activate `prod` or to modify
  `clusters/base` as part of this dev-only feature.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The foundation MUST target exactly one development environment in
  the project's single AWS account and MUST use the canonical environment name
  `dev`.
- **FR-002**: Dev MUST use dedicated VPC range `10.10.0.0/16`; later staging
  and production specs MUST use non-overlapping `10.20.0.0/16` and
  `10.30.0.0/16` ranges respectively.
- **FR-003**: The dev network MUST span at least two distinct availability zones,
  keep Kubernetes workers off direct public ingress, and retain an explicit path
  for approved public entry points.
- **FR-004**: The foundation MUST provide one managed EKS cluster for dev with
  sufficient initial worker capacity to host ArgoCD, the already validated
  platform add-ons, Redis, and the five current business services without
  depending on Karpenter for bootstrap.
- **FR-005**: The EKS cluster MUST use Kubernetes 1.35. Any move to a newer minor
  version requires an explicit compatibility risk and live proof because KEDA
  2.20.1 and Kyverno 1.18.2 document tested ranges ending at 1.35.
- **FR-006**: The foundation MUST provide immutable ECR repositories for
  `auth-api`, `todos-api`, `users-api`, `frontend`, and
  `log-message-processor`, and MUST expose their registry/repository locations
  for later digest-pinned GitOps overlays.
- **FR-007**: Registry controls MUST prevent mutable-tag replacement, encrypt
  stored images, scan pushed images, and support retention without treating a
  tag as artifact identity.
- **FR-008**: The cluster MUST expose an IAM OIDC trust foundation that allows an
  explicitly named Kubernetes service account in an explicitly named namespace
  to assume only its approved IAM role without stored AWS access keys.
- **FR-009**: Workload identity configuration MUST reject wildcard trust across
  namespaces or service accounts and MUST not grant an application permission
  merely because it runs on a worker node.
- **FR-010**: Dev foundation state MUST be stored remotely in S3 with encryption,
  blocked public access, version recovery, and native S3 lockfile locking that
  prevents concurrent state mutation; a new DynamoDB lock table MUST NOT be
  introduced.
- **FR-011**: The dev state address and lock identity MUST be deterministic and
  environment-qualified so future staging and production states cannot collide
  with it.
- **FR-012**: State backend creation and foundation planning MUST be separate,
  documented operations so the foundation never attempts to create the backend
  in the same state that depends on that backend.
- **FR-013**: The repository MUST provide one documented dev entry point that
  performs initialization, configuration validation, and plan generation in no
  more than four teammate commands after prerequisites are satisfied.
- **FR-014**: The preview workflow MUST use short-lived or federated AWS
  credentials and MUST neither require nor document committed access keys.
- **FR-015**: The foundation MUST publish a GitOps handoff containing the dev EKS
  API endpoint and certificate authority for operator/bootstrap use, `dev`
  environment identifier, derived `microtodo-dev` namespace, the
  `https://kubernetes.default.svc` in-cluster activation server, ECR
  registry/repository locations, and cluster identity values.
- **FR-016**: The handoff MUST map to the existing value-only mechanism: a future
  `clusters/eks-dev` sibling consumes `clusters/base`;
  `cluster-registration` injects reviewed `repoURL` and `revision`; the
  apps and environments activation patches inject `env: dev` and
  `server: https://kubernetes.default.svc`; application overlays supply ECR
  `newName` and an immutable OCI digest.
- **FR-017**: The handoff MUST identify the remaining GitOps gaps without
  attempting to implement them: the local registration owns duplicated
  replacement wiring and the future-EKS conformance fixture is unfinished. It
  MUST rely on the now-explicit per-cluster ArgoCD/in-cluster topology and the
  corrected inventory of four controller add-ons plus Redis as the fifth
  infrastructure root.
- **FR-018**: Terraform MUST NOT write to
  `microservice-app-gitops`, register the cluster in ArgoCD, install ArgoCD or
  the provider-neutral platform add-ons, or activate a business-service overlay
  as part of this feature.
- **FR-019**: The foundation MUST use a managed node group for bootstrap and
  preserve the network discovery and least-privilege identity boundaries needed
  for later Karpenter adoption, but Karpenter controller installation,
  Karpenter-managed capacity, and interruption handling are outside this feature.
- **FR-020**: Staging, production, the economical single-cluster profile, Azure
  AKS disaster recovery, cross-cloud routing, and ECR-to-ACR replication are
  outside this feature.
- **FR-021**: Existing Azure backend, base-infrastructure, container-app, and
  workflow resources MUST remain independently operable and MUST not be imported
  into or destroyed by the AWS dev state.
- **FR-022**: All created resources and outputs MUST carry unambiguous project,
  environment, ownership, and management metadata suitable for cost and audit
  attribution.
- **FR-023**: The dev EKS public API CIDR MUST be exactly `0.0.0.0/0` as an
  explicit small-team/dynamic-IP tradeoff, with authorization enforced by IAM
  and exact EKS access entries. Changing this dev value requires a reviewed
  decision; staging and production MUST use more restrictive CIDRs.

### Key Entities

- **Dev Foundation**: The environment-qualified collection of network, cluster,
  registry, IAM, and backend integrations owned by this feature.
- **Remote State Namespace**: The unique dev state address, recovery history, and
  lock identity used by the team.
- **Workload Identity Binding**: The exact relationship among an EKS OIDC issuer,
  one Kubernetes namespace/service account subject, one IAM role, and its
  approved permissions.
- **Image Repository Set**: The five ECR repositories that retain scanned,
  encrypted images whose OCI digests are promoted through GitOps.
- **GitOps Registration Handoff**: The non-secret infrastructure values needed
  by a later `clusters/eks-dev` value-only registration and dev overlays.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A teammate with prerequisites can produce the complete dev
  foundation plan in no more than four documented commands and without entering
  an internal module directory.
- **SC-002**: One hundred percent of planned resources are attributable to
  `dev`, and the plan contains zero staging, production, AKS, or legacy Azure
  mutations.
- **SC-003**: The planned network uses at least two availability zones, and one
  availability-zone loss does not remove all planned Kubernetes worker capacity.
- **SC-004**: All five current business-service ECR repositories enforce
  immutable tags, encryption, and push scanning, while later deployment inputs
  identify images by OCI digest.
- **SC-005**: A concurrent second writer is denied the dev state lock, and a
  future environment's backend address differs from the dev address before any
  cloud mutation occurs.
- **SC-006**: Static review finds zero committed AWS access keys, zero wildcard
  workload-identity subjects, and zero workload policies inherited solely from
  the worker-node role.
- **SC-007**: The GitOps handoff maps every infrastructure-owned value to the
  intended sibling-registration and activation fields, names every current
  GitOps gap, and requires zero future redesign of the Terraform outputs after
  GitOps resolves its own registration wiring and server mode.
- **SC-008**: Two consecutive plans with unchanged configuration and remote state
  report no infrastructure drift after the foundation is provisioned.
- **SC-009**: All repository formatting, initialization, configuration
  validation, and plan-contract checks pass without an apply operation.

## Assumptions

- The full profile remains the ratified default, so dev receives its own VPC and
  EKS cluster; adopting one shared EKS cluster with namespace-only isolation
  requires a separate constitution amendment.
- Team members authenticate to the existing AWS account through approved
  short-lived or federated credentials supplied outside the repository.
- Dev uses the human-approved account `995253610162`, region `us-east-1`, three
  named AZs, VPC/subnet allocation, global dev API CIDR, and Terraform operator
  role committed as non-secret team configuration. Credentials remain external.
- The remote-state bootstrap is a one-time prerequisite with its own state
  lifecycle; this feature documents it but never runs it implicitly.
- Initial EKS worker capacity is required because Karpenter is not installed by
  this feature.
- Git source URL and revision are GitOps-owned review values and are not Terraform
  outputs; Terraform supplies only infrastructure-derived registration values.
- The current GitOps checkout has live local proof for its platform add-ons, but
  not completed future-EKS value-only conformance; that gap is a separate GitOps
  dependency and is not evidence against the AWS foundation plan itself.
- Provider-specific External Secrets, certificate issuer, ingress, and workload
  role bindings are added later as registration/environment resources while the
  shared add-on installations remain unchanged.
