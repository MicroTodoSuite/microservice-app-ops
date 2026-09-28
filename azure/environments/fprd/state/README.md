# fprd Azure state

Step 1 of 6 of the Azure disaster-recovery estate (gitops
`specs/009-full-platform-rollout` user story 5). This root holds the fprd Azure state backend: the resource group and the encrypted, Entra-only, zone-redundant storage account whose `tfstate` container holds every other fprd Azure root's state. It is the one Azure root on local state (PC-IAC-008 adaptation); its `terraform.tfstate` is gitignored and backed up under `~/backups-microtodosuite/` before every apply.

Every module comes from `terraform-azure-modules` by exact tag (MTS-IAC-102).

## Before any plan

1. The DR preflight (spec 009 T124, `scripts/preflight/azure-dr.sh`) verifies
   the subscription, region, ranges, providers, and quota.
2. Copy `fprd.tfvars.example` to `fprd.tfvars`
   (gitignored) and fill the verified values.

## Plan (never a convenience apply)

```bash
terraform init` (local state)
terraform plan -var-file=fprd.tfvars -out=state.tfplan
```

An apply uses only a saved plan a maintainer approved, after an external state
backup or a `no-prior-state` receipt (MTS-IAC-107).

## Tests

`terraform test` runs the offline contract in `tests/state.tftest.hcl`.
