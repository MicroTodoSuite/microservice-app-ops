# fprd Azure networking

Step 2 of 6 of the Azure disaster-recovery estate (gitops
`specs/009-full-platform-rollout` user story 5). This root holds the DR VNet with one private node subnet (Key Vault and Storage service endpoints), and the Terraform-owned Standard static ingress address in its own resource group, whose name and resource group the AKS Istio Service annotations bind to (T129). It also holds `enable_active_active`, which defaults to false and cannot be set to true until a replicated data store exists (constitution principle 12). It looks up the state roots' resources by standard name, so those roots are applied first.

Every module comes from `terraform-azure-modules` by exact tag (MTS-IAC-102).

## Before any plan

1. The DR preflight (spec 009 T124, `scripts/preflight/azure-dr.sh`) verifies
   the subscription, region, ranges, providers, and quota.
2. Copy `fprd.tfvars.example` to `fprd.tfvars` and `networking.azurerm.tfbackend.example` to `networking.azurerm.tfbackend`
   (gitignored) and fill the verified values.

## Plan (never a convenience apply)

```bash
terraform init -backend-config=networking.azurerm.tfbackend
terraform plan -var-file=fprd.tfvars -out=networking.tfplan
```

An apply uses only a saved plan a maintainer approved, after an external state
backup or a `no-prior-state` receipt (MTS-IAC-107).

## Tests

`terraform test` runs the offline contract in `tests/networking.tftest.hcl`.
