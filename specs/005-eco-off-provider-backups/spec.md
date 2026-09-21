# Feature Specification: Off-Provider Backups for the Economical Profile

**Feature Branch**: `test/eco-off-provider-backups`

**Created**: 2026-09-21

**Status**: Draft — specification and failing contracts only

**Input**: The maintainer chose option A on 2026-09-21: the economical profile keeps
its optional cold disaster recovery in Azure as backup storage only. ADR-0001
("Off-provider backups", "Recovery objectives") and the constitution's economical
baseline ("optional cold DR via Velero backups to an off-provider store in Azure, so
that a lost AWS account does not take the backups with it") already name it.

## Context

Today every copy of the economical environment's recovery material lives in the
AWS account it must survive: the Terraform state of `eco` and `shd` in the S3
bucket `lex-mts-shd-s3-tfstate-<account>`, and no cluster backup at all. The
project has already lost two AWS accounts (PC-IAC-008). If a third loss happened
today, rebuilding `eco` would start from source alone, with no state to import
against and no Kubernetes objects to restore.

This feature adds one Azure storage account, on the "Azure for Students"
subscription, that holds two things and nothing else:

1. replicas of every `eco` and `shd` Terraform state object in the S3 bucket;
2. Velero backups of the `eco` cluster.

The economical profile gains **no functional component in Azure**: no cluster,
no registry, no Key Vault, no network. The warm-standby AKS estate of the full
profile (gitops spec 009, user story 5) is separate and unaffected.

## Clarifications

### Session 2026-09-21

- **Q**: What does the economical profile run in Azure?
  **A**: Backup storage only — one resource group, one storage account, two
  private containers, and the identities and role assignments that let the
  replication job and Velero write to them. Maintainer decision, option A.
- **Q**: Which subscription?
  **A**: "Azure for Students". The subscription ID is configuration in the
  operator-owned `eco.tfvars`, never a literal in a tracked file (MTS-IAC-103
  applied to Azure).
- **Q**: How is the Azure storage root structured under the IaC rules?
  **A**: As live roots that consume modules from `terraform-azure-modules` by
  exact tag (MTS-IAC-102) and never contain one. `terraform-azure-modules` holds
  no module on its `main` on 2026-09-21 (only `_template/`; its pull request #2
  was closed by maintainer decision), so this feature adds the four modules it
  needs there first (T004–T007). The live roots are split by domain
  (PC-IAC-022): `azure/environments/eco/workload` owns the resource group, the
  storage account, and its containers, like an AWS application bucket;
  `azure/environments/eco/security` owns the identities, federated credentials,
  and role assignments.
- **Q**: Why is the workload root applied before the security root, the reverse
  of PC-IAC-022's order?
  **A**: Every role assignment is scoped to one container, which exists only
  after the workload root. This mirrors the recorded IRSA exception of the AWS
  environments: one second security pass, recorded once for `eco` in Azure.
- **Q**: Where does the Azure roots' own Terraform state live?
  **A**: Not in the S3 bucket, which is exactly what must not be a single point of
  failure. It lives in an Azure state backend (MTS-IAC-104): a dedicated storage
  account in `azure/environments/shd/state`, which starts with local state backed
  up externally (PC-IAC-008), exactly as the AWS `shd/state` root did. If the
  gitops spec 009 T124 preflight has already approved an Azure backend by then,
  the maintainer chooses whether both share it (decision D2).
- **Q**: How do the replication job and Velero authenticate without shared keys?
  **A**: The storage account refuses Shared Key authorization, so every request is
  authorized by Microsoft Entra ID. The replication job uses GitHub OIDC
  federated to a user-assigned managed identity, the same pattern as
  `azure/login` with OpenID Connect. Velero uses the Azure plugin with
  `useAAD: "true"`, which needs `Storage Blob Data Contributor` on its container;
  its credential file reaches the cluster only through External Secrets
  (decision D1 records the credential type).
- **Q**: What network exposure does the account have?
  **A**: Public endpoint enabled but no anonymous or key-based access: nested
  items cannot be made public, shared keys are refused, HTTPS only, TLS 1.2
  minimum. A private endpoint is out of reach — the writers are GitHub-hosted
  runners and an EKS cluster whose NAT addresses change on every economical
  `up`. MTS-IAC-104's "public network access disabled where the runner can still
  reach it" therefore does not apply; decision D3 records it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Keep a copy of the platform's Terraform state outside AWS (Priority: P1)

A platform operator can rely on every `eco` and `shd` Terraform state object in
the S3 state bucket having a recent, verifiable copy in Azure, so that losing the
AWS account does not also lose the record of what was deployed.

**Independent Test**: Run the replication workflow's contract offline; after
activation, dispatch the workflow once and compare its manifest's SHA-256 values
with the S3 objects.

**Acceptance Scenarios**:

1. **Given** the S3 bucket holds `eco/*/terraform.tfstate` and
   `shd/*/terraform.tfstate`, **When** the scheduled replication runs, **Then**
   each object is written under the same key to the `tfstate-replicas`
   container, with a manifest recording its key, S3 version ID, size, and
   SHA-256.
2. **Given** the workflow runs, **When** it authenticates, **Then** it uses only
   GitHub OIDC to AWS and to Azure; no access key, client secret, SAS token, or
   storage account key exists anywhere in the job.
3. **Given** a state object that was overwritten or deleted in Azure, **When** an
   operator looks for the earlier copy, **Then** blob versioning and soft delete
   still hold it for the retention period.
4. **Given** the lock files Terraform's native S3 locking writes (`*.tflock`),
   **When** the job copies the prefixes, **Then** it skips them.

### User Story 2 - Back up the economical cluster to a store outside AWS (Priority: P1)

A platform operator can rely on Velero, installed on the `eco` cluster by ArgoCD,
writing scheduled backups of the economical namespaces to Azure Blob storage.
The GitOps side is `microservice-app-gitops` spec 012; this repository owns the
storage, the identity, and the AWS secret container Velero's credentials live in.

**Acceptance Scenarios**:

1. **Given** the `eco` cluster is active, **When** Velero's schedule fires,
   **Then** a backup of the `dev`, `staging`, `prod`, and `demo` namespaces lands
   in the `velero-eco` container.
2. **Given** the credentials Velero needs, **When** they reach the cluster,
   **Then** they come from AWS Secrets Manager through External Secrets, never
   from Git.
3. **Given** Velero's Azure identity, **When** its role assignments are listed,
   **Then** it holds `Storage Blob Data Contributor` on the `velero-eco`
   container only, and nothing on `tfstate-replicas`.

### User Story 3 - Prove the recovery by rebuilding eco from the copies (Priority: P2)

A platform operator can run a restore drill that rebuilds `eco` using only the
Azure copies — the replicated state and the Velero backup — and records the
measured RTO and RPO against the targets below.

**Acceptance Scenarios**:

1. **Given** the drill starts, **When** the operator reconstructs state, **Then**
   the state objects are downloaded from `tfstate-replicas` and each SHA-256 is
   checked against the replication manifest before any plan runs.
2. **Given** the restored state, **When** the operator plans `eco`, **Then** the
   plan is reviewed and applied only as a saved plan, after the external backup
   MTS-IAC-107 requires.
3. **Given** the rebuilt cluster with Velero reconciled by ArgoCD, **When** the
   operator restores the latest backup, **Then** the drill record states the
   start and end times, the backup's timestamp, and the resulting RTO and RPO.

## Recovery objectives

The targets refine ADR-0001's "RPO: the last backup for `eco`" for the economical
profile. They are targets; only the drill (US3, T030) measures them.

| Item | RPO target | RTO target | Basis |
| --- | --- | --- | --- |
| Terraform state of `eco` and `shd` | 6 hours | — (part of the rebuild below) | The replication job runs every 6 hours and on dispatch; the operator dispatches it after every apply, so a recorded apply is copied within minutes |
| `eco` Kubernetes objects and file-system volume data | 24 hours | — (part of the rebuild below) | Velero's daily schedule; ADR-0001 |
| Container images | 0 | — | Rebuilt by digest from the service repositories; the full profile's ACR mirror is out of scope here |
| Redis and other in-memory data | Not recoverable | — | Redis is ephemeral by design (constitution principle 12); the loss is disclosed, not hidden |
| Rebuilding `eco` in a replacement AWS account from the Azure copies | — | 8 hours | Account bootstrap, `shd` and `eco` plans and applies from restored state, ArgoCD bootstrap, Velero restore |
| Restoring `eco` workloads into an intact cluster | — | 1 hour | Velero restore only |

While `eco` is down under the profile lifecycle, Velero does not run; the RPO of
cluster data is then measured from the last backup taken before the down
transition, and the down procedure records that backup's name (FR-016).

## Requirements *(mandatory)*

### Functional Requirements

**Azure storage (workload root)**

- **FR-001**: `azure/environments/eco/workload` MUST create exactly one resource
  group `lex-mts-eco-rg-backups` and one storage account `lexmtsecostbackups`
  (MTS-IAC-101's separator-free form for storage accounts), through modules from
  `terraform-azure-modules` pinned by `?ref=<module>-v<MAJOR>.<MINOR>.<PATCH>`.
- **FR-002**: The storage account MUST be `StorageV2`, `Standard`, with
  `min_tls_version = "TLS1_2"`, `https_traffic_only_enabled = true`,
  `shared_access_key_enabled = false`, `allow_nested_items_to_be_public = false`,
  `infrastructure_encryption_enabled = true`,
  `cross_tenant_replication_enabled = false`, and
  `default_to_oauth_authentication = true`.
- **FR-003**: Its blob properties MUST enable versioning and keep deleted blobs
  and deleted containers for 30 days each; `permanent_delete_enabled` MUST stay
  `false`.
- **FR-004**: It MUST hold exactly two containers, both `private`:
  `tfstate-replicas` and `velero-eco`.
- **FR-005**: The replication type MUST be an input with the default `LRS`
  (decision D4); the root MUST reject any value AzureRM does not accept.
- **FR-006**: The root MUST configure `provider "azurerm"` with
  `alias = "principal"`, `use_oidc = true`, `storage_use_azuread = true`, the
  subscription from configuration, and `features {}`; its backend MUST be a
  partial `backend "azurerm" {}` whose example uses Entra ID authentication and
  the key `eco/workload/terraform.tfstate` (PC-IAC-008, MTS-IAC-104).
- **FR-007**: Every resource MUST carry `tags = merge(var.common_tags,
  { Name = <name> }, var.additional_tags)` through the modules, with the
  governance tags of `eco` (MTS-IAC-104, PC-IAC-004).
- **FR-008**: The root MUST expose `backup_storage_contract_data`: the effective
  names, the security settings of FR-002 and FR-003, and the containers with
  their access types, read from the modules' outputs — never recomputed from
  the root's own inputs — plus the storage account ID and blob endpoint.
- **FR-009**: No tracked file MAY carry a subscription ID, tenant ID, access key,
  SAS token, connection string, or client secret; no output MAY expose one.

**Azure identities (security root)**

- **FR-010**: `azure/environments/eco/security` MUST create the user-assigned
  managed identity `lex-mts-eco-id-tfstaterep` with exactly one federated
  credential: issuer `https://token.actions.githubusercontent.com`, audience
  `api://AzureADTokenExchange`, subject
  `repo:MicroTodoSuite/microservice-app-ops:environment:offsite-backups`.
- **FR-011**: It MUST grant that identity `Storage Blob Data Contributor` scoped
  to the `tfstate-replicas` container only.
- **FR-012**: It MUST grant Velero's principal (D1) `Storage Blob Data
  Contributor` scoped to the `velero-eco` container only.
- **FR-013**: It MUST read the storage account and containers through data
  sources (PC-IAC-017) and create no storage resource itself.

**State replication (GitHub Actions)**

- **FR-014**: `.github/workflows/eco-state-replication.yml` MUST run on a
  schedule every 6 hours and on `workflow_dispatch`, never on `push` or
  `pull_request`; it MUST run in the GitHub environment `offsite-backups`, with a
  concurrency group that never cancels a running copy.
- **FR-015**: It MUST declare `permissions` of exactly `contents: read` and
  `id-token: write`; pin every action by full commit SHA (MTS-IAC-106); assume
  the AWS role `lex-mts-shd-role-tfstaterep` through OIDC, with the account ID
  and region from repository variables; log in to Azure through OIDC; and use
  `--auth-mode login` for every blob command.
- **FR-016**: It MUST copy every object under the `eco/` and `shd/` prefixes
  except `*.tflock`, write each under the same key in `tfstate-replicas`, and
  upload a manifest `manifests/<UTC timestamp>.json` listing key, S3 version ID,
  size, and SHA-256; it MUST fail if any SHA-256 read back from Azure differs.
- **FR-017**: It MUST never print state content, never run `terraform`, and
  never delete an object in either store.
- **FR-018**: `aws/environments/shd/security` MUST add the role
  `lex-mts-shd-role-tfstaterep`, trusted only for the subject
  `repo:MicroTodoSuite/microservice-app-ops:environment:offsite-backups`, allowed
  `s3:ListBucket` on the state bucket for the two prefixes, `s3:GetObject` and
  `s3:GetObjectVersion` on them, and `kms:Decrypt` on the state key — and nothing
  else.

**Velero prerequisites in AWS**

- **FR-019**: `aws/environments/eco/security` MUST add the Secrets Manager
  container `lex-mts-eco-sm-velero` with no value; a human writes the value
  (PC-IAC-016), in the shape Velero's credentials file takes.
- **FR-020**: `aws/environments/eco/security-irsa` MUST add the IRSA role
  `lex-mts-eco-role-velerosec`, trusted only for
  `system:serviceaccount:velero:velero-external-secrets`, allowed only
  `secretsmanager:GetSecretValue` on `lex-mts-eco-sm-velero`.

**Recovery**

- **FR-021**: `docs/eco-off-provider-recovery.md` MUST describe the restore drill
  step by step, with the evidence each step records.
- **FR-022**: Every economical `down` MUST record the name and completion time
  of the latest successful Velero backup beside the lifecycle bundle, so the RPO
  of a later recovery is known.

### Key Entities

- **Replica container** `tfstate-replicas`: current copies of the state objects
  under their S3 keys, older copies as blob versions, and one manifest per run.
- **Backup container** `velero-eco`: Velero's backup tarballs, metadata, and
  Kopia repository for file-system volume backups.
- **Replication manifest**: the evidence that a copy matches its source.
- **Drill record**: `docs/evidence/eco-off-provider-drill-<date>.md`, the only
  place a measured RTO or RPO may be claimed.

## Success Criteria *(mandatory)*

- **SC-001**: `terraform test` in `azure/environments/eco/workload` passes offline
  against a mock AzureRM provider and proves FR-001 to FR-008.
- **SC-002**: `terraform test` in `azure/environments/eco/security` passes offline
  and proves FR-010 to FR-013.
- **SC-003**: `tests/contract/azure-eco-backups.sh` passes: module sources, the
  backend, the provider, and the absence of static credentials (FR-001, FR-006,
  FR-009).
- **SC-004**: `tests/workflows/eco-state-replication.bats` passes (FR-014 to
  FR-017).
- **SC-005**: One dispatched run writes a manifest whose every SHA-256 matches
  the S3 source, and the workflow run URL is recorded in T026.
- **SC-006**: One drill rebuilds `eco` from the Azure copies alone and records a
  measured RTO and RPO; the drill passes only if both meet the targets above, and
  a miss is recorded as a miss.

## Decisions for the maintainer

- **D1 — Velero's credential type.** Recommended: a Microsoft Entra application
  with a client secret (the plugin's first method), created and rotated by a
  human, its secret written only to `lex-mts-eco-sm-velero` and synced by
  External Secrets. Its object ID is an input of the security root. Workload
  identity federation (the plugin's third method) needs no secret, but the `eco`
  cluster is destroyed and recreated by the lifecycle, and every new cluster has
  a new OIDC issuer, so the federated credential would need an Azure apply after
  every economical `up`. Open risk: the tenant behind "Azure for Students" may
  forbid app registrations; T003 checks it before anything is built.
- **D2 — Azure state backend.** Recommended: `azure/environments/shd/state`
  creates `lex-mts-shd-rg-tfstate` and `lexmtsshdsttfstate`, shared later by the
  DR roots. The alternative waits for gitops spec 009 T124's backend.
- **D3 — Public endpoint.** Recommended: enabled, with Entra-only authorization
  (FR-002), because neither writer has a stable address or a private path.
- **D4 — Redundancy.** Recommended: `LRS`, for the student credit; `GRS` doubles
  the storage price and protects against the loss of the Azure region, which is
  outside this feature's threat model (loss of the AWS account).
- **D5 — Retention.** Recommended: 30 days for blob and container soft delete,
  and 30 days of Velero backups (gitops spec 012).

## Out of Scope

- Any functional Azure component for the economical profile: compute, network,
  registry, Key Vault, DNS.
- The full profile's warm-standby AKS estate and its ACR mirror (gitops spec 009
  US5).
- Replicating `shd/state`, which has local state backed up externally by
  MTS-IAC-107, and the legacy roots' state keys.
- Automatic failover, and restoring Redis data.
- Taking an automatic Velero backup before every economical `down`; FR-022 only
  records the last one.
- Applying anything while this specification is in draft.
