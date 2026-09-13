# shd/security

The account-level security root of the rebuilt layout (ops spec 004 T010,
ai-agents specs/001 T025). It holds what every environment shares:

| Resource | Module | Name |
| --- | --- | --- |
| GitHub Actions OIDC provider, adopted from the account by an `import` block | `iam-oidc-provider-v1.0.0` | the issuer URL; `Name` tag `lex-mts-shd-oidc-github` |
| Role the services' main-branch workflows assume to push images | `iam-role-v1.0.0` | `lex-mts-shd-role-ecrpublish` |
| Key that encrypts every environment's VPC flow-log group | `kms-key-v1.0.0` | `alias/lex-mts-shd-kms-flowlogs` |
| Role that delivers VPC flow logs | `iam-role-v1.0.0` | `lex-mts-shd-role-flowlogs` |

**The publisher role** trusts only tokens with the STS audience from the
`main` branch of the listed repositories of `github_organization`. It may push
only to `lex-mts-shd-ecr-<key>` for the listed keys, which `shd/registry`
creates.

**The flow-log role** may be assumed by the VPC Flow Logs service only for
flow logs of this account (`aws:SourceAccount`, `aws:SourceArn`), and it
writes only to `/aws/vpc-flow-logs/*` groups. Because those groups are
encrypted with a customer managed key, the role may also use that one key,
only through CloudWatch Logs (`kms:ViaService`). **The key** lets CloudWatch Logs
in this region use it only for those groups, through the
`kms:EncryptionContext:aws:logs:arn` condition. The `network` module of every
environment receives both through its `flow_log` input.

The Terraform deploy role and the Kyverno image verifier are not here yet.
The deploy role's permissions are designed in their own change. The verifier
trusts the clusters' OIDC issuers, which exist only once the `workload` roots
do.

## Plan and apply

```bash
cp shd.tfvars.example shd.tfvars                         # fill aws_account_id
cp security.s3.tfbackend.example security.s3.tfbackend   # fill from shd/state's outputs
terraform -chdir=aws/environments/shd/security init -backend-config=security.s3.tfbackend
terraform -chdir=aws/environments/shd/security plan -input=false -var-file=shd.tfvars -out=shd-security.tfplan
```

The first plan imports the existing GitHub OIDC provider instead of creating
it. An apply uses only that saved plan, after the maintainer approves it and
after a timestamped state backup (MTS-IAC-107).

## Outputs

`github_oidc_provider_arn`, `ecr_publisher_role_arn`, `flow_log_key_arn`, and
`flow_log_role_arn`.
