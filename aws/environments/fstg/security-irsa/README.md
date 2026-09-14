# fstg/security-irsa

The full staging environment's IRSA pass, the second security root that
PC-IAC-022 records. It runs after `fstg/workload`, because every role here
trusts that cluster's OIDC issuer.

| Resource | Module | Name |
| --- | --- | --- |
| IAM OIDC provider of the cluster's issuer, audience `sts.amazonaws.com` | `iam-oidc-provider-v1.0.0` | the issuer URL; `Name` tag `lex-mts-fstg-oidc-eks` |
| JWT signing secret readers, one per application environment | `iam-role-v1.0.0` | `lex-mts-fstg-role-jwt<code>` |
| Alertmanager Slack webhook reader | `iam-role-v1.0.0` | `lex-mts-fstg-role-obssecret` |
| Falcosidekick Slack webhook reader | `iam-role-v1.0.0` | `lex-mts-fstg-role-secsecret` |
| Trivy Operator image reader | `iam-role-v1.0.0` | `lex-mts-fstg-role-trivyecr` |
| Kyverno image verifier | `iam-role-v1.0.0` | `lex-mts-fstg-role-kyvernoecr` |

**Trust.** Every role trusts only this cluster's OIDC provider, with the
`sts.amazonaws.com` audience and one exact service account:

| Role | Service account | Grants |
| --- | --- | --- |
| `jwt<code>` | `<namespace>/external-secrets-jwt` | `DescribeSecret` and `GetSecretValue` on `lex-mts-fstg-sm-jwt<code>` |
| `obssecret` | `observability/observability-external-secrets-jwt` | the same, on `lex-mts-fstg-sm-slackobs` |
| `secsecret` | `security/security-external-secrets-jwt` | the same, on `lex-mts-fstg-sm-slacksec` |
| `trivyecr` | `security/trivy-operator` | ECR authentication; `BatchGetImage` and `GetDownloadUrlForLayer` on `lex-mts-shd-ecr-<key>` |
| `kyvernoecr` | `kyverno/kyverno-admission-controller` | ECR authentication; `BatchCheckLayerAvailability`, `BatchGetImage`, `DescribeImages`, and `GetDownloadUrlForLayer` on `lex-mts-shd-ecr-<key>` |

The secrets are `fstg/security`'s and the image repositories are
`shd/registry`'s, both read by their standard names. This root creates no
secret and no repository.

**Why a second pass.** An IRSA role trusts the cluster's OIDC provider, which
exists only after `fstg/workload`. The directory name is not a domain name the
contracts accept, so `docs/iac-exceptions.md` records the PC-IAC-022
exception, as it does for every environment's IRSA pass.

**Why IRSA and not Pod Identity.** The AWS add-ons use EKS Pod Identity roles
in `fstg/security`. The in-cluster applications cannot: the External Secrets
stores authenticate through `auth.jwt.serviceAccountRef`, which is IRSA.

## Plan and apply

```bash
cp fstg.tfvars.example fstg.tfvars                                   # fill aws_account_id
cp security-irsa.s3.tfbackend.example security-irsa.s3.tfbackend  # fill from shd/state's outputs
terraform -chdir=aws/environments/fstg/security-irsa init -backend-config=security-irsa.s3.tfbackend
terraform -chdir=aws/environments/fstg/security-irsa plan -input=false -var-file=fstg.tfvars -out=fstg-security-irsa.tfplan
```

An apply uses only that saved plan, after the maintainer approves it
(MTS-IAC-107), and after `fstg/workload`. The lifecycle plans this root last
going up and first going down (`docs/aws-profile-lifecycle.md`).

## Outputs

- `oidc_provider_arn`
- `irsa_role_arns`, keyed by `jwt<code>`, `obssecret`, `secsecret`,
  `trivyecr`, and `kyvernoecr`: the values the GitOps annotations take
