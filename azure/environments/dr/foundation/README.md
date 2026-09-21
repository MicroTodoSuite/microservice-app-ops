# Azure disaster-recovery foundation

The Terraform root of the Azure disaster-recovery estate (gitops
`specs/009-full-platform-rollout` T126, contract T119). It calls
`azure/modules/aks-foundation` once, with names built from the `fprd`
governance prefix, the four approved operator `/32` addresses, the exact
four-name Secrets Manager to Key Vault mapping, the three External Secrets
reader service accounts, the `azure-dr` seed subject, and
`enable_active_active = false`, which the root refuses to change.

It holds its own state under `fprd/dr-foundation/terraform.tfstate` in the
approved Azure Blob backend, locked by blob leases.

## Before any plan

1. T124 runs `scripts/preflight/azure-dr.sh` against the real account and
   verifies the subscription, location, backend, VNet collision check,
   providers, and AKS 1.35 availability.
2. Copy `foundation.azurerm.tfbackend.example` to `foundation.azurerm.tfbackend`
   and `fprd.tfvars.example` to `fprd.tfvars` (both gitignored), and fill them
   with the verified values.

## Plan (never a convenience apply)

```bash
terraform init -backend-config=foundation.azurerm.tfbackend
terraform plan -var-file=fprd.tfvars -out=dr-foundation.tfplan
```

An apply uses only a saved plan a maintainer approved, after an external state
backup or a `no-prior-state` receipt (MTS-IAC-107, spec 009 T127-T128).

## Checks

- `terraform test` runs the offline contract in `tests/foundation.tftest.hcl`.
- `tests/contract/azure-dr-foundation.sh` checks the backend, the absence of
  secrets and static credentials, and the provider pins.
- `.github/workflows/azure-dr-foundation-checks.yml` runs both on every pull
  request, estimates cost with Infracost, and, once enabled, produces a
  plan-only refresh through Azure OIDC.
