# shd/state

The account-level Terraform state backend of the rebuilt layout (ops spec 004,
ai-agents specs/001 T025). It creates the bucket
`lex-mts-shd-s3-tfstate-<account>` and the rotating key
`alias/lex-mts-shd-kms-tfstate` through the `state-backend` module
(`state-backend-v1.0.0`). Every other root stores its state there under
`<environment>/<domain>/terraform.tfstate`, with native S3 locking.

This root replaces `aws/environments/dev/backend`. Its bucket and key are new;
the legacy bucket keeps the legacy roots' state until the rebuild retires them
(ops spec 004 T026).

## Local state

This is the only root with local state (PC-IAC-008 adaptation): it creates the
bucket the other backends use. `terraform.tfstate` is gitignored and is the
sole record of the bucket and the key, so it is copied to
`~/backups-microtodosuite/` before every apply and never deleted.

## Plan and apply

```bash
cp shd.tfvars.example shd.tfvars   # fill aws_account_id from config/aws-account.env
terraform -chdir=aws/environments/shd/state init
terraform -chdir=aws/environments/shd/state plan -input=false -var-file=shd.tfvars -out=shd-state.tfplan
```

An apply uses only that saved plan, after the maintainer approves it and
after a `no-prior-state` receipt for the first apply (MTS-IAC-107).

## Inputs

| Name | Description |
| --- | --- |
| `client`, `project`, `environment` | Governance codes; `environment` is always `shd` |
| `aws_account_id` | `AWS_ACCOUNT_ID` from `config/aws-account.env` |
| `aws_region` | Region of the account-level resources |
| `deploy_role_arn` | Role Terraform assumes |
| `owner`, `cost_center`, `repository` | Transversal tags; defaults `platform`, `microtodosuite`, and this repository |

## Outputs

`state_bucket_name`, `state_bucket_arn`, `state_kms_key_arn`,
`state_kms_alias_name`: the values every other root's `.s3.tfbackend` needs.
