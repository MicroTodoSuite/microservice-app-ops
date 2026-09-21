# fprd Azure registry

Step 3 of 6 of the Azure disaster-recovery estate (gitops
`specs/009-full-platform-rollout` user story 5). This root holds the DR container registry the mirror workflows copy the signed service and platform graphs into (T131), with no admin user and no anonymous pull. It looks up the state roots' resources by standard name, so those roots are applied first.

Every module comes from `terraform-azure-modules` by exact tag (MTS-IAC-102).

## Before any plan

1. The DR preflight (spec 009 T124, `scripts/preflight/azure-dr.sh`) verifies
   the subscription, region, ranges, providers, and quota.
2. Copy `fprd.tfvars.example` to `fprd.tfvars` and `registry.azurerm.tfbackend.example` to `registry.azurerm.tfbackend`
   (gitignored) and fill the verified values.

## Plan (never a convenience apply)

```bash
terraform init -backend-config=registry.azurerm.tfbackend
terraform plan -var-file=fprd.tfvars -out=registry.tfplan
```

An apply uses only a saved plan a maintainer approved, after an external state
backup or a `no-prior-state` receipt (MTS-IAC-107).

## Tests

`terraform test` runs the offline contract in `tests/registry.tftest.hcl`.
