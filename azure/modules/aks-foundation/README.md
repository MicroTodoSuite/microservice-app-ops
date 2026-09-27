# aks-foundation

The Azure disaster-recovery foundation of MicroTodoSuite (gitops
`specs/009-full-platform-rollout` T125, contract T118). It creates:

- a DR resource group and a dedicated ingress resource group;
- a VNet with one private node subnet (no default outbound access), with
  Key Vault and Storage service endpoints;
- an AKS 1.35 cluster on Azure CNI Overlay with the Cilium data plane and
  network policy, the OIDC issuer and workload identity, Entra ID RBAC with
  local accounts disabled, an API allowlist of `/32` operator addresses, and a
  bounded cluster autoscaler (node auto-provisioning off) that fits the
  regional vCPU quota;
- pre-created cluster and kubelet identities; the cluster identity holds
  `Network Contributor` on the node subnet and the ingress resource group and
  `Managed Identity Operator` on the kubelet identity only;
- `Azure Kubernetes Service RBAC Cluster Admin` for the named operators only;
- an ACR with no admin user and no anonymous pull; the kubelet identity holds
  `AcrPull` on it;
- an **empty** Key Vault: RBAC only, purge protection, `prevent_destroy`, and a
  firewall that denies by default and admits the node subnet and the reviewed
  `/32` addresses. A reader identity holds `Key Vault Secrets User` and trusts
  one exact in-cluster service account per federated credential. A seed
  identity holds a custom role limited to get, set, and read-metadata and trusts
  exact GitHub `repo:<owner>/<repo>:environment:<environment>` subjects. The
  module declares no `azurerm_key_vault_secret`: only the seed workflow writes
  values;
- an encrypted recovery storage account: infrastructure encryption, HTTPS with
  TLS 1.2, no shared key, no public blobs, versioning, soft delete, and a
  firewall that admits the node subnet only;
- a Standard static public IP with a tenant-scoped DNS label, which the GitOps
  Istio Service selects by name and resource group.

## Files

Resources are split the way spec 009 T125 names them: `main.tf` (resource
group, cluster, recovery storage), `network.tf`, `identity.tf`, `registry.tf`,
`secrets.tf`, and `ingress.tf`. PC-IAC-001 allows resources in `main.tf` only,
and MTS-IAC-102 places modules in `terraform-azure-modules`; both conflicts are
recorded for a maintainer decision, not waived.

## Requirements

- Terraform `>= 1.15.8`, AzureRM `>= 5.0.1`.
- The root passes its `azurerm.principal` provider as `azurerm.project`
  (MTS-IAC-104) and configures `storage_use_azuread = true`, because the storage
  account refuses shared keys.
- Subscription, location, every range, and the vCPU quota are the values the DR
  preflight (`scripts/preflight/azure-dr.sh`, spec 009 T124) verifies.

## Inputs

| Name | Description |
| --- | --- |
| `client`, `project`, `environment` | Governance codes (MTS-IAC-101). |
| `subscription_id` | Approved subscription; the plan stops if the authenticated client is elsewhere. |
| `location` | Programmatic location name, such as `eastus2`. |
| `names` | Physical names built in the root: 14 keys, checked against the governance prefix. |
| `kubernetes_version` | `1.35` or `1.35.x`. |
| `reserved_cidrs` | Connected networks (every AWS VPC) no Azure range may overlap. |
| `vnet_cidr`, `node_subnet_cidr`, `pod_cidr`, `service_cidr`, `dns_service_ip` | Verified, mutually non-overlapping ranges. |
| `api_server_authorized_ip_ranges` | `/32` operator addresses for the API server; never `0.0.0.0/0`. |
| `key_vault_allowed_cidrs` | `/32` addresses the Key Vault firewall admits besides the node subnet. |
| `system_node_pool` | `vm_size`, `vcpus`, `min_count`, `max_count` of the autoscaled system pool. |
| `regional_vcpu_quota` | The regional vCPU quota `max_count * vcpus` must fit. |
| `cluster_admin_principal_ids` | Entra object IDs granted cluster administration. |
| `key_vault_reader_service_accounts` | Map of `{namespace, name}` the reader identity trusts. |
| `github_seed_subjects` | Exact GitHub subjects the seed identity trusts. |
| `ingress_dns_label` | DNS label of the ingress public IP. |
| `common_tags`, `additional_tags` | Tags merged into every resource with its `Name`. |

## Outputs

`resource_group_name`, `cluster_name`, `oidc_issuer_url`, `kubernetes_version`,
`api_server_authorized_cidrs`, `key_vault_name`, `key_vault_url`,
`key_vault_reader_client_id`, `github_seed_client_id`, `container_registry_name`,
`container_registry_endpoint`, `storage_account_name`, `ingress_public_ip_name`,
`ingress_public_ip_resource_group_name`, `ingress_public_ip_endpoint`, and
`ingress_public_ip_dns_name`. None carries a credential or a kubeconfig.

## Example

See [`sample/`](sample/). The live call is
`azure/environments/dr/foundation/main.tf`.

## Tests

`terraform init -backend=false && terraform test` runs the offline contract in
`tests/aks-foundation.tftest.hcl` against a mock provider.
