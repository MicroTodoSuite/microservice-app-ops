# fprd Azure workload

Step 5 of 6 of the Azure disaster-recovery estate (gitops
`specs/009-full-platform-rollout` user story 5). This root holds the AKS 1.35 DR cluster (Azure CNI Overlay with Cilium, workload identity, Entra admin groups, local accounts disabled, the four-address API allowlist, a quota-bounded autoscaler), bound to the networking root's subnet and the security root's identities by name, and the encrypted recovery storage for off-provider copies. It looks up the networking and security roots' resources by standard name, so those roots are applied first.

Every module comes from `terraform-azure-modules` by exact tag (MTS-IAC-102).

## Before any plan

1. The DR preflight (spec 009 T124, `scripts/preflight/azure-dr.sh`) verifies
   the subscription, region, ranges, providers, and quota.
2. Copy `fprd.tfvars.example` to `fprd.tfvars` and `workload.azurerm.tfbackend.example` to `workload.azurerm.tfbackend`
   (gitignored) and fill the verified values.

## Plan (never a convenience apply)

```bash
terraform init -backend-config=workload.azurerm.tfbackend
terraform plan -var-file=fprd.tfvars -out=workload.tfplan
```

An apply uses only a saved plan a maintainer approved, after an external state
backup or a `no-prior-state` receipt (MTS-IAC-107).

## Tests

`terraform test` runs the offline contract in `tests/workload.tftest.hcl`.
