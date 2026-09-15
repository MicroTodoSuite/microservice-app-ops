# Tasks: Profile-Aware AWS Runtime Lifecycle (003)

- [X] **T001 Specify the lifecycle boundary and operator contracts**
  - [X] Record durable and runtime resource classes
  - [X] Record economical and full profile composition and ordering
  - [X] Record the GitOps quiescence and saved-plan gates

- [X] **T002 Commit the failing lifecycle contract**
  - [X] Require the new wrapper and exact profile/direction vocabulary
  - [X] Require a default-on `runtime_enabled` input in every foundation root
  - [X] Require plan provenance and durable-deletion guards

- [X] **T003 Implement the state-safe runtime boundary**
  - [X] Conditionalize VPC, EKS, nodes, add-ons, flow logs, and cluster-scoped identities
  - [X] Add explicit `moved` blocks for singleton address migrations
  - [X] Preserve ECR, Secrets Manager, Route 53, and GitHub publication resources
  - [X] Make runtime outputs null or empty while disabled

- [X] **T004 Implement profile orchestration**
  - [X] Add economical and full root inventories and dependency order
  - [X] Add AWS account, local configuration, Git cleanliness, and tool preflight
  - [X] Create saved plans, JSON evidence, checksums, and metadata
  - [X] Validate plan provenance and apply only exact saved plans
  - [X] Require a GitOps revision for down transitions

- [X] **T005 Document operation and prerequisites**
  - [X] Document AWS login renewal for the configured source and role profiles
  - [X] Document exact economical and full commands
  - [X] Document pinned local-tool installation and verification
  - [X] Document residual durable cost and persistent-data warnings

- [X] **T006 Verify without mutating AWS**
  - [X] Run Terraform formatting, validation, and tests
  - [X] Run shell contracts and ShellCheck
  - [X] Run live AWS identity and profile preflight
  - [X] Record that no plan apply or destroy was executed

- [ ] **T007 Complete live acceptance in a separate approved operation**
  - [ ] Review a refresh-backed enabled migration plan with no physical replacements
  - [ ] Review economical down plan JSON and persistent-data disposition
  - [ ] Apply the approved shutdown bundle
  - [ ] Restore through a separately reviewed economical up bundle
  - [ ] Migrate and accept full-profile roots before their first replacement-account apply

- [X] **T008 Make the operator lifecycle portable on the documented workstation**
  - [X] Commit a failing contract that rejects a mandatory ripgrep dependency
  - [X] Use stock GNU grep for wrapper state checks
  - [X] Document ripgrep as optional rather than preinstalled
  - [X] Verify economical preflight without ripgrep on `PATH`

- [X] **T009 Add a Make-based operator interface without weakening lifecycle gates**
  - [X] Extend the specification and plan with the Make command contract
  - [X] Commit a failing contract for both profiles and every lifecycle phase
  - [X] Implement explicit profile, bundle, and GitOps revision validation
  - [X] Delegate each target to exactly one lifecycle-wrapper command
  - [X] Document Make as the primary operator interface
  - [X] Run the Make interface contract in the required AWS foundation gate
  - [X] Verify dry runs and rejection paths without contacting AWS

- [X] **T010 Keep full-profile prose on the primary Make interface**
  - [X] Commit a failing contract for the two stale direct-wrapper references
  - [X] Replace the stale check and plan syntax in the runbook
  - [X] Re-run the Make interface contract

- [X] **T011 Distinguish runtime EKS OIDC from durable GitHub OIDC during shutdown audit** — every subtask was already ticked; the address-aware filter is `scripts/aws-profile-durable-deletes.jq`, and `tests/contract/aws-profile-lifecycle.sh` keeps a runtime EKS OIDC provider removable while the GitHub OIDC provider and ECR stay protected
  - [X] Inspect the failed economical plan and identify the EKS issuer and exact resource address
  - [X] Commit a failing behavioral contract for runtime EKS OIDC, durable GitHub OIDC, and ECR
  - [X] Replace the broad provider-type match with a versioned address-aware durable filter
  - [X] Re-audit the captured economical plan without applying it
  - [X] Verify bundle `economical-down-20260911T151126Z` with 96 runtime deletes, zero durable deletes, and valid checksums; retain the apply gate

- [X] **T012 Normalize saved-plan bundle paths before Terraform changes directory**
  - [X] Reproduce the relative-bundle failure with a behavioral contract
  - [X] Resolve relative and absolute bundle inputs to one canonical directory
  - [X] Verify inspect and apply retain the saved-plan checksum and provenance gates

- [X] **T013 Snapshot persistent volumes before GitOps quiescence (ai-agents specs/001 T038)**
  - [X] Record the 2026-09-11 loss mechanism and the maintainer's decision in the specification and plan
  - [X] Commit failing contracts for the snapshot command, the down-plan record gate, and the Make interface
  - [X] Snapshot every EBS CSI volume through the EC2 API, with explicit consent as the only alternative
  - [X] Require a record that predates quiescence, covers every present volume, and has completed snapshots
  - [X] Carry the record in the checksummed down bundle and require it at apply
  - [X] Document the ordering in the runbook

- [X] **T014 Map the lifecycle onto the rebuilt roots (ai-agents specs/001 T027)**
  - [X] Record the root classes, the second bundles, and the delegated decision in the specification and plan
  - [X] Commit failing contracts for the eco records, the NAT egress switch, both second bundles, the egress filter, and the declared account
  - [X] Add `nat_gateways_enabled` to eco/networking and `cluster_deletion_protection` to eco/workload, both defaulting on
  - [X] Plan the eco roots in dependency order with both second bundles, and audit the networking down plan with the egress filter
  - [X] Compare the STS account with `config/aws-account.env` and each root's `aws_account_id`
  - [X] Document the boundary, the second bundles, and the legacy release in the runbook
  - [X] Map the full profile onto `shd/networking` and the `fdev`, `fstg`, and `fprd` roots after ops spec 004 T012
    - [X] Commit failing contracts for the full records, the hub-first bundle, the spokes' transit switch, and the transit deletions of the egress filter, and failing Terraform tests in the three spokes
    - [X] Add `transit_enabled` to the three spokes, defaulting on, with the hub lookups conditional on it
    - [X] Plan the full roots in dependency order with the hub-first and unprotect bundles, and audit each spoke's down plan with the egress filter
    - [X] Document the full boundary and the second bundles in the runbook and the spoke READMEs

- [ ] **T015 Preserve durable DNS while shutting down the economical ingress runtime**
  - [X] Commit a failing contract that distinguishes the ALB aliases from the durable ACM validation record
  - [X] Restrict the unprotect pass to the EKS cluster resource
  - [X] Allow the economical ALB aliases to leave with the runtime while retaining every other Route 53 record
  - [ ] Target the economical cluster and ingress runtime without destroying the colocated ACM resources
  - [ ] Re-plan and inspect both economical shutdown bundles before apply
