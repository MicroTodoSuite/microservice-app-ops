# eco/security-irsa

The economical environment's IRSA pass, the second security root that
PC-IAC-022 records (ops spec 004 T011, ai-agents specs/001 T025). It runs
after `eco/workload`, because every role here trusts the cluster's OIDC
issuer.

| Resource | Module | Name |
| --- | --- | --- |
| IAM OIDC provider of the cluster's issuer, audience `sts.amazonaws.com` | `iam-oidc-provider-v1.0.0` | the issuer URL; `Name` tag `lex-mts-eco-oidc-eks` |
| JWT signing secret readers, one per application environment | `iam-role-v1.0.0` | `lex-mts-eco-role-jwt{dev,stg,prd,dmo}` |
| Alertmanager Slack webhook reader | `iam-role-v1.0.0` | `lex-mts-eco-role-obssecret` |
| Falcosidekick Slack webhook reader | `iam-role-v1.0.0` | `lex-mts-eco-role-secsecret` |
| Trivy Operator image reader | `iam-role-v1.0.0` | `lex-mts-eco-role-trivyecr` |
| Kyverno image verifier | `iam-role-v1.0.0` | `lex-mts-eco-role-kyvernoecr` |

**Trust.** Every role trusts only the cluster's OIDC provider, with the
`sts.amazonaws.com` audience and one exact service account:

| Role | Service account | Grants |
| --- | --- | --- |
| `jwt<code>` | `<namespace>/external-secrets-jwt` | `DescribeSecret` and `GetSecretValue` on `lex-mts-eco-sm-jwt<code>` |
| `obssecret` | `observability/observability-external-secrets-jwt` | the same, on `lex-mts-eco-sm-slackobs` |
| `secsecret` | `security/security-external-secrets-jwt` | the same, on `lex-mts-eco-sm-slacksec` |
| `trivyecr` | `security/trivy-operator` | ECR authentication; `BatchGetImage` and `GetDownloadUrlForLayer` on `lex-mts-shd-ecr-<key>` |
| `kyvernoecr` | `kyverno/kyverno-admission-controller` | ECR authentication; `BatchCheckLayerAvailability`, `BatchGetImage`, `DescribeImages`, and `GetDownloadUrlForLayer` on `lex-mts-shd-ecr-<key>` |

The service accounts and permissions are the legacy dev roles', which the
GitOps manifests annotate. The secrets and the image repositories are read
from `eco/security` and `shd/registry` by name.

## Why IRSA, and why a second pass

**Why these apps stay on IRSA.** The AWS add-ons (vpc-cni and the EBS CSI
driver) use EKS Pod Identity roles in `eco/security`. The in-cluster
applications cannot: the External Secrets stores authenticate through
`auth.jwt.serviceAccountRef`, which exchanges a service account token for a
role, and that is IRSA.

**Why a second pass.** An IRSA role trusts the cluster's OIDC provider, which
exists only after `eco/workload`. The roles therefore come in this second
security pass. Its directory name is not a domain name the contracts accept,
so `docs/iac-exceptions.md` records it as the PC-IAC-022 exception.

## Two changes from the spec 004 inventory

- **The Kyverno verifier is here, not in `shd/security`.** The plan named it
  `lex-mts-shd-role-kyvernoecr`, but its trust needs this cluster's issuer,
  which `shd/security` applies long before. Each environment's IRSA pass
  holds its own verifier.
- **The Trivy Operator reader is added.** The legacy dev root created it, and
  GitOps annotates `security/trivy-operator` with it, but the plan's inventory
  omitted it.

## Plan and apply

```bash
cp eco.tfvars.example eco.tfvars                                  # fill aws_account_id
cp security-irsa.s3.tfbackend.example security-irsa.s3.tfbackend  # fill from shd/state's outputs
terraform -chdir=aws/environments/eco/security-irsa init -backend-config=security-irsa.s3.tfbackend
terraform -chdir=aws/environments/eco/security-irsa plan -input=false -var-file=eco.tfvars -out=eco-security-irsa.tfplan
```

An apply uses only that saved plan, after the maintainer approves it
(MTS-IAC-107), and after `eco/workload`. The state key is new, so the apply
records a `no-prior-state` receipt.

## Outputs

- `oidc_provider_arn`
- `irsa_role_arns`, keyed by `jwt<code>`, `obssecret`, `secsecret`,
  `trivyecr`, and `kyvernoecr`: the values the GitOps annotations take
  (ops spec 004 T016)
