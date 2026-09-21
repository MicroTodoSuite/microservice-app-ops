# fprd Azure security

Step 4 of 6 of the Azure disaster-recovery estate (gitops
`specs/009-full-platform-rollout` user story 5). This root holds the empty, RBAC-only Key Vault closed to all but the four operator addresses and the node subnet; the exact four-name Secrets Manager to Key Vault mapping; the cluster identity (Network Contributor on the node subnet and the ingress resource group, Managed Identity Operator on the kubelet identity); the kubelet identity (AcrPull on the registry); and the seed identity, trusted only by the `azure-dr` environment of the organization's `.github` repository, with get, set, and read-metadata on the vault alone. It looks up the networking and registry roots' resources by standard name, so those roots are applied first.

Every module comes from `terraform-azure-modules` by exact tag (MTS-IAC-102).

## Before any plan

1. The DR preflight (spec 009 T124, `scripts/preflight/azure-dr.sh`) verifies
   the subscription, region, ranges, providers, and quota.
2. Copy `fprd.tfvars.example` to `fprd.tfvars` and `security.azurerm.tfbackend.example` to `security.azurerm.tfbackend`
   (gitignored) and fill the verified values.

## Plan (never a convenience apply)

```bash
terraform init -backend-config=security.azurerm.tfbackend
terraform plan -var-file=fprd.tfvars -out=security.tfplan
```

An apply uses only a saved plan a maintainer approved, after an external state
backup or a `no-prior-state` receipt (MTS-IAC-107).

## Tests

`terraform test` runs the offline contract in `tests/security.tftest.hcl`.
