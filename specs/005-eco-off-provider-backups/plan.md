# Implementation Plan: Off-Provider Backups for the Economical Profile

**Spec**: [spec.md](spec.md) · **Tasks**: [tasks.md](tasks.md) · **Companion**:
`microservice-app-gitops` spec 012 (`specs/012-eco-velero-offsite-backups/`),
which installs Velero on `eco`.

## Summary

One Azure storage account on the "Azure for Students" subscription receives two
streams: a GitHub Actions job that copies `eco` and `shd` Terraform state from S3
every 6 hours, and Velero on the `eco` cluster. Both write through Microsoft
Entra ID; the account refuses shared keys. A drill proves that `eco` can be
rebuilt from those copies alone.

## Technical context

| Item | Choice | Source |
| --- | --- | --- |
| Terraform | `>= 1.15.8`, as `.terraform-version` | PC-IAC-006 |
| AzureRM | `hashicorp/azurerm` 5.6.0, the latest release on 2026-09-21 | terraform MCP `get_latest_provider_version` |
| Modules | `git::https://github.com/MicroTodoSuite/terraform-azure-modules.git//<module>?ref=<module>-vX.Y.Z` | MTS-IAC-102 |
| Subscription | "Azure for Students", from `eco.tfvars` | Maintainer, 2026-09-21 |
| Location | An environment parameter; ADR-0001 names Central US or South Central US | MTS-IAC-103 |
| Velero | Server 1.18.x with `velero-plugin-for-microsoft-azure` 1.14.x, pinned by digest in gitops spec 012 | Plugin compatibility table |

## Repository layout

```text
azure/environments/shd/state/          # D2: Azure state backend, local state (T008)
azure/environments/eco/workload/       # RG, storage account, two containers (T011)
  tests/workload.tftest.hcl            # failing contract (T002)
azure/environments/eco/security/       # replication identity, role assignments (T012)
  tests/security.tftest.hcl            # failing contract (T002)
tests/contract/azure-eco-backups.sh    # source contract (T002)
tests/workflows/eco-state-replication.bats  # workflow contract (T002)
.github/workflows/eco-state-replication.yml # replication job (T014)
docs/eco-off-provider-recovery.md      # drill runbook (T028)
```

`terraform-azure-modules` gains `resource-group`, `storage-account`,
`managed-identity`, and `role-assignment` (T004–T007), each with its own
`CHANGELOG.md`, `sample/`, tests, and release-please component.

## Design

### Why the storage account is a workload resource

PC-IAC-022 places application buckets in the workload domain, and the storage
account is their Azure counterpart. Identities and role assignments are security.
The resource group is created with the account, in the workload root, and the
security root reads both through data sources. The resulting order — workload,
then security — is the one recorded exception for `eco` in Azure, justified in
the spec's clarifications.

### Module outputs the roots depend on

The roots' contracts assert on what the modules report, not on what the roots
pass in, so a module that silently ignored an input would fail them:

| Module | Outputs the root reads |
| --- | --- |
| `resource-group` | `name`, `id`, `location` |
| `storage-account` | `name`, `id`, `primary_blob_endpoint`, `security_settings` (every FR-002 and FR-003 attribute as applied to the resource), `containers` (map of name to `{ id, access_type, resource_manager_id }`) |
| `managed-identity` | `id`, `principal_id`, `client_id`, `federated_credentials` (map of name to `{ issuer, subject, audience }`) |
| `role-assignment` | `assignments` (map of key to `{ scope, role_definition_name, principal_id }`) |

### Authentication

| Writer | Azure identity | Authorization |
| --- | --- | --- |
| Replication job | `lex-mts-eco-id-tfstaterep`, GitHub OIDC | `Storage Blob Data Contributor` on `tfstate-replicas` |
| Velero | D1: Entra application (recommended) | `Storage Blob Data Contributor` on `velero-eco` |
| Operator (drill) | Their own Entra account | `Storage Blob Data Reader` granted for the drill, revoked after |

### Replication job

1. `aws-actions/configure-aws-credentials` assumes `lex-mts-shd-role-tfstaterep`.
2. `aws s3 cp --recursive` of `eco/` and `shd/` into a runner temporary
   directory, excluding `*.tflock`; `aws s3api list-object-versions` supplies each
   key's current version ID.
3. `azure/login` with the identity's client ID, the tenant ID, and the subscription
   ID from repository variables.
4. `az storage blob upload-batch --auth-mode login --overwrite` into
   `tfstate-replicas`, then the manifest.
5. `az storage blob download` of each key, SHA-256 compared with the manifest;
   any difference fails the run.
6. The temporary directory is removed in an `always()` step.

No step echoes a state file. Versioning keeps every overwritten copy.

## Verification strategy

- **Offline, every pull request**: the two `terraform test` suites with
  `mock_provider "azurerm"` and `command = plan`; the source contract; the
  workflow contract. None needs credentials or a backend.
- **Before implementation**: the four contracts fail, which is the evidence of
  this pull request.
- **Live**: the first dispatched replication run (T026), and the drill (T030).
- **Dev plan invariance**: nothing here changes an `aws/` root until T016–T018;
  those tasks re-run the `eco` and `shd` plans and confirm from the plan JSON
  that only the new resources are added.

## Documentation consulted (2026-09-21)

- terraform MCP: `get_latest_provider_version hashicorp/azurerm` → 5.6.0;
  `get_provider_details` for `azurerm_storage_account` (5.6.0: `min_tls_version`,
  `shared_access_key_enabled` and its `storage_use_azuread` note,
  `infrastructure_encryption_enabled` forcing a new resource,
  `public_network_access` enum, `blob_properties.versioning_enabled`,
  `delete_retention_policy`, `container_delete_retention_policy`),
  `azurerm_storage_container` (`storage_account_id`, `container_access_type`),
  `azurerm_federated_identity_credential` (`user_assigned_identity_id`,
  `audience`, `issuer`, `subject`).
- microsoft-learn MCP (`microsoft_docs_search`): "Prevent Shared Key
  authorization for an Azure Storage account"; "Enable infrastructure encryption
  for double encryption of data"; "Use the Azure Login action with OpenID
  Connect"; "Configure an app to trust an external identity provider" (subject
  and `api://AzureADTokenExchange` audience); "Back up and restore workload
  clusters by using Velero" (credential file variables).
- aws-knowledge MCP (`search_documentation`): customer managed KMS keys require
  `kms:Decrypt` for the reader of SSE-KMS objects.
- Vendor site, because no documentation MCP server covers Velero:
  `vmware-tanzu/velero-plugin-for-microsoft-azure` README (authentication
  methods, `Storage Blob Data Contributor` with `useAAD`, compatibility table)
  and `backupstoragelocation.md` (`useAAD`, `storageAccountURI`); latest releases
  on 2026-09-21: plugin v1.14.3, Velero v1.18.3.
