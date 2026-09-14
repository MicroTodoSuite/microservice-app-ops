# fprd/security-irsa

The full production environment's IRSA pass, the second security root that
PC-IAC-022 records. It runs after `fprd/workload`, because every role here
trusts that cluster's OIDC issuer.

| Resource | Module | Name |
| --- | --- | --- |
| IAM OIDC provider of the cluster's issuer, audience `sts.amazonaws.com` | `iam-oidc-provider-v1.0.0` | the issuer URL; `Name` tag `lex-mts-fprd-oidc-eks` |
| JWT signing secret readers, one per application environment | `iam-role-v1.0.0` | `lex-mts-fprd-role-jwt<code>` |
| Alertmanager Slack webhook reader | `iam-role-v1.0.0` | `lex-mts-fprd-role-obssecret` |
| Falcosidekick Slack webhook reader | `iam-role-v1.0.0` | `lex-mts-fprd-role-secsecret` |
| Trivy Operator image reader | `iam-role-v1.0.0` | `lex-mts-fprd-role-trivyecr` |
| Kyverno image verifier | `iam-role-v1.0.0` | `lex-mts-fprd-role-kyvernoecr` |
| Karpenter controller | `iam-role-v1.0.0` | `lex-mts-fprd-role-karpenter` |

**Trust.** Every role trusts only this cluster's OIDC provider, with the
`sts.amazonaws.com` audience and one exact service account:

| Role | Service account | Grants |
| --- | --- | --- |
| `jwt<code>` | `<namespace>/external-secrets-jwt` | `DescribeSecret` and `GetSecretValue` on `lex-mts-fprd-sm-jwt<code>` |
| `obssecret` | `observability/observability-external-secrets-jwt` | the same, on `lex-mts-fprd-sm-slackobs` |
| `secsecret` | `security/security-external-secrets-jwt` | the same, on `lex-mts-fprd-sm-slacksec` |
| `trivyecr` | `security/trivy-operator` | ECR authentication; `BatchGetImage` and `GetDownloadUrlForLayer` on `lex-mts-shd-ecr-<key>` |
| `kyvernoecr` | `kyverno/kyverno-admission-controller` | ECR authentication; `BatchCheckLayerAvailability`, `BatchGetImage`, `DescribeImages`, and `GetDownloadUrlForLayer` on `lex-mts-shd-ecr-<key>` |
| `karpenter` | `kube-system/karpenter` | the eighteen statements of Karpenter's reference template, scoped to this cluster |

The secrets are `fprd/security`'s and the image repositories are
`shd/registry`'s, both read by their standard names. This root creates no
secret and no repository.

**Why a second pass.** An IRSA role trusts the cluster's OIDC provider, which
exists only after `fprd/workload`. The directory name is not a domain name the
contracts accept, so `docs/iac-exceptions.md` records the PC-IAC-022
exception, as it does for every environment's IRSA pass.

**Why IRSA and not Pod Identity.** The AWS add-ons use EKS Pod Identity roles
in `fprd/security`. The in-cluster applications cannot: the External Secrets
stores authenticate through `auth.jwt.serviceAccountRef`, which is IRSA.

## The Karpenter controller role

Its permissions are Karpenter's reference CloudFormation template
(`karpenter.sh/docs/reference/cloudformation/`, read 2026-09-14). The
reference's six managed policies become the eighteen statements of one inline
policy, each keeping the reference's own statement identifier, so a reader can
line them up against the upstream document:

| Reference policy | Statements |
| --- | --- |
| Node lifecycle | `AllowScopedEC2InstanceAccessActions`, `AllowScopedEC2LaunchTemplateAccessActions`, `AllowScopedEC2InstanceActionsWithTags`, `AllowScopedResourceCreationTagging`, `AllowScopedResourceTagging`, `AllowScopedDeletion` |
| IAM integration | `AllowPassingInstanceRole`, `AllowScopedInstanceProfileCreationActions`, `AllowScopedInstanceProfileTagActions`, `AllowScopedInstanceProfileActions` |
| EKS integration | `AllowAPIServerEndpointDiscovery` |
| Interruption | `AllowInterruptionQueueActions` |
| Zonal shift | `AllowZonalShiftStatusReadOnly` |
| Resource discovery | `AllowRegionalReadActions`, `AllowSSMReadActions`, `AllowPricingReadActions`, `AllowUnscopedInstanceProfileListAction`, `AllowInstanceProfileReadActions` |

Every scoped statement is confined to this cluster's
`kubernetes.io/cluster/lex-mts-fprd-eks-main` ownership tag, this region, and
this account: the controller may launch, tag, and terminate only what this
cluster owns, poll only `lex-mts-fprd-sqs-karpenter`, describe only
`lex-mts-fprd-eks-main`, and pass only `lex-mts-fprd-role-node`. One inline
policy keeps the role within the 10240 characters IAM allows; the document is
6165 of them, and a test holds that line.

The queue is `fprd/workload`'s and the node role is `fprd/security`'s, both read
by their standard names.

## Plan and apply

```bash
cp fprd.tfvars.example fprd.tfvars                                   # fill aws_account_id
cp security-irsa.s3.tfbackend.example security-irsa.s3.tfbackend  # fill from shd/state's outputs
terraform -chdir=aws/environments/fprd/security-irsa init -backend-config=security-irsa.s3.tfbackend
terraform -chdir=aws/environments/fprd/security-irsa plan -input=false -var-file=fprd.tfvars -out=fprd-security-irsa.tfplan
```

An apply uses only that saved plan, after the maintainer approves it
(MTS-IAC-107), and after `fprd/workload`. The lifecycle plans this root last
going up and first going down (`docs/aws-profile-lifecycle.md`).

## Outputs

- `oidc_provider_arn`
- `irsa_role_arns`, keyed by `jwt<code>`, `obssecret`, `secsecret`,
  `trivyecr`, `kyvernoecr`, and `karpenter`: the values the GitOps annotations
  take
