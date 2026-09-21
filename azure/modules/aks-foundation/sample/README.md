# aks-foundation sample

A runnable call of the module with local state. Fill `subscription_id`,
`operator_cidrs`, `cluster_admin_principal_ids`, and `github_seed_subjects` in
`terraform.tfvars`, then:

```bash
terraform init
terraform plan -out=sample.tfplan
```

Never apply the sample against the DR subscription; the live call is
`azure/environments/dr/foundation`.
