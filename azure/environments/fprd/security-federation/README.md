# fprd Azure security-federation

Step 6 of 6 of the Azure disaster-recovery estate (gitops
`specs/009-full-platform-rollout` user story 5). This root holds the second security pass. The reader identity trusts the cluster's OIDC issuer, which exists only after the workload root, so it runs last, as the AWS `security-irsa` roots do. The reader holds Key Vault Secrets User on the DR vault, and only the three External Secrets service accounts can federate to it. It looks up the workload and security roots' resources by standard name, so those roots are applied first.

Every module comes from `terraform-azure-modules` by exact tag (MTS-IAC-102).

## Before any plan

1. The DR preflight (spec 009 T124, `scripts/preflight/azure-dr.sh`) verifies
   the subscription, region, ranges, providers, and quota.
2. Copy `fprd.tfvars.example` to `fprd.tfvars` and `security-federation.azurerm.tfbackend.example` to `security-federation.azurerm.tfbackend`
   (gitignored) and fill the verified values.

## Plan (never a convenience apply)

```bash
terraform init -backend-config=security-federation.azurerm.tfbackend
terraform plan -var-file=fprd.tfvars -out=security-federation.tfplan
```

An apply uses only a saved plan a maintainer approved, after an external state
backup or a `no-prior-state` receipt (MTS-IAC-107).

## Tests

`terraform test` runs the offline contract in `tests/security-federation.tftest.hcl`.
