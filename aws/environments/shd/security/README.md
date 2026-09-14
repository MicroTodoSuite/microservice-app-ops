# shd/security

The account-level security root of the rebuilt layout (ops spec 004 T010,
ai-agents specs/001 T025). It holds what every environment shares:

| Resource | Module | Name |
| --- | --- | --- |
| GitHub Actions OIDC provider, adopted from the account by an `import` block | `iam-oidc-provider-v1.0.0` | the issuer URL; `Name` tag `lex-mts-shd-oidc-github` |
| Terraform deploy role | `iam-role-v1.0.0` | `lex-mts-shd-role-tfdeploy` |
| Role the services' main-branch workflows assume to push images | `iam-role-v1.0.0` | `lex-mts-shd-role-ecrpublish` |
| Key that encrypts every environment's VPC flow-log group | `kms-key-v1.0.0` | `alias/lex-mts-shd-kms-flowlogs` |
| Role that delivers VPC flow logs | `iam-role-v1.0.0` | `lex-mts-shd-role-flowlogs` |
| Key that encrypts the state trail's logs | `kms-key-v1.0.0` | `alias/lex-mts-shd-kms-cloudtrail` |
| Trail recording every read and write of the Terraform state, and its log bucket | `cloudtrail-trail-v1.0.0` | `lex-mts-shd-ct-tfstate`; bucket `lex-mts-shd-s3-cloudtrail-<account>` |

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

**The state trail** records the S3 object-level data events of
`lex-mts-shd-s3-tfstate-<account>`, which `shd/state` owns and this root reads
by name: who read or wrote which state file, and when (ai-agents specs/001
T043). It records no management events. Its logs are encrypted with
`lex-mts-shd-kms-cloudtrail` and validated with digest files, and they expire
after `trail_log_retention_in_days`, 365 by default. The key lets CloudTrail
generate data keys and describe the key only for this trail (`aws:SourceArn`).
A reader of the logs needs `kms:Decrypt` on the key, granted in IAM. Why a
trail and not CloudTrail Lake, and why its log bucket carries no access logs,
is recorded in the `cloudtrail-trail` module and in terraform-aws-modules
`docs/iac-exceptions.md`.

**The Kyverno image verifier** is not here. It trusts a cluster's OIDC issuer,
so each environment's IRSA pass holds its own (`<env>/security-irsa`).

## The deploy role

`lex-mts-shd-role-tfdeploy` replaces the hand-made `microtodosuite-terraform-dev`
(ops spec 004 plan: create first, retire last). Every rebuilt root assumes it
through `deploy_role_arn`.

**Trust.** Only the IAM users or roles in `deploy_role_operator_arns` may
assume it, and only with MFA (`aws:MultiFactorAuthPresent`). The session that
calls `sts:AssumeRole` must carry MFA, for example credentials from
`aws sts get-session-token --serial-number … --token-code …`.

**Permissions.** It gets `PowerUserAccess`, which grants every service except
IAM, Organizations, and Account (it keeps service-linked roles). An inline
policy adds the IAM that the roots need, and nothing wider:

| Statement | What it allows |
| --- | --- |
| `ManageProjectRoles` | Create, read, tag, update, and delete roles named `lex-mts-*`, and their inline policies |
| `AttachOnlyTheReviewedManagedPolicies` | Attach or detach only `AmazonEKSClusterPolicy`, `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly`, `AmazonEKS_CNI_Policy`, and `AmazonEBSCSIDriverPolicy` (`iam:PolicyARN`) |
| `ManageProjectOidcProviders` | The GitHub provider and the EKS issuers of this region |
| `ListOidcProviders` | The one listing action that takes no resource |
| `PassPodIdentityRolesToEks` | Pass `lex-mts-*-role-{vpccni,ebscsi}` only to `pods.eks.amazonaws.com` |
| `PassClusterNodeAndFlowLogRoles` | Pass `lex-mts-*-role-{cluster,node}` and `lex-mts-shd-role-flowlogs` |
| `DenyChangingTheDeployRoleItself` | Denies every write to `lex-mts-shd-role-tfdeploy` |
| `DenyAssumingProjectRoles` | Denies `sts:AssumeRole` on every `lex-mts-*` role |

**Bootstrap.** Because the role may not change itself, an account IAM
administrator runs the apply that creates it and any later apply that changes
it (ai-agents T029, with the maintainer's approval). After that, the roots
switch `deploy_role_arn` to its ARN, and `microtodosuite-terraform-dev` is
retired last (ops spec 004 T026).

**What it does not prevent.** The role can still write any inline policy on a
`lex-mts-*` role, and set that role's trust. A compromised operator session
could therefore create a role for another principal. MFA on the trust, the
exact principal list, and CloudTrail are the controls. A permissions boundary
on every project role would close that gap; it needs every root to set one, and
it is not part of this change.

**Not yet verified.** The action list is the legacy role's IAM set, plus what
the rebuilt roots use: managed-policy attachments, role updates, and instance
profile listing before a role is deleted. The first real plan and apply at
T029 is its test. Any `AccessDenied` is added narrowly, in a reviewed change.

## Plan and apply

```bash
cp shd.tfvars.example shd.tfvars                         # fill aws_account_id and the operators
cp security.s3.tfbackend.example security.s3.tfbackend   # fill from shd/state's outputs
terraform -chdir=aws/environments/shd/security init -backend-config=security.s3.tfbackend
terraform -chdir=aws/environments/shd/security plan -input=false -var-file=shd.tfvars -out=shd-security.tfplan
```

The first plan imports the existing GitHub OIDC provider instead of creating
it. An apply uses only that saved plan, after the maintainer approves it and
after a timestamped state backup (MTS-IAC-107).

## Outputs

`github_oidc_provider_arn`, `deploy_role_arn`, `ecr_publisher_role_arn`,
`flow_log_key_arn`, and `flow_log_role_arn`.
