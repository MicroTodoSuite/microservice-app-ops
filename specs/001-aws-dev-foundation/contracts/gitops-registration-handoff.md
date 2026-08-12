# Contract: GitOps Registration Handoff

## Purpose and ownership

This contract prevents the AWS foundation from guessing how GitOps works. It
maps Terraform-owned outputs to the current, validated registration seam in
`microservice-app-gitops` and records gaps that GitOps must resolve in a later
feature.

Terraform owns VPC, EKS, IAM/IRSA, ECR, and the outputs below. GitOps owns
`repoURL`, `revision`, ArgoCD, root Applications, activation lists, application
overlays, OCI digests, provider-specific Kubernetes resources, and all shared
platform add-on manifests. This feature writes nothing to the GitOps repository.

## Foundation output schema

The dev foundation exposes one non-sensitive `gitops_handoff` object:

```hcl
object({
  environment                        = string
  namespace                          = string
  activation_server                  = string
  aws_region                         = string
  cluster_name                       = string
  cluster_arn                        = string
  cluster_endpoint                   = string
  cluster_certificate_authority_data = string
  oidc_issuer_url                    = string
  oidc_provider_arn                  = string
  ecr_repository_urls                = map(string)
  irsa_role_arns                     = map(string)
  private_subnet_ids                 = list(string)
  karpenter_security_group_id        = string
})
```

Required fixed/derived values are:

```text
environment       = dev
namespace         = microtodo-dev
activation_server = https://kubernetes.default.svc
```

The ECR map has exactly `auth-api`, `todos-api`, `users-api`, `frontend`, and
`log-message-processor` keys.

## Mapping to the current mechanism

| Foundation value | Actual later GitOps consumer | Notes |
| --- | --- | --- |
| `environment` | `clusters/eks-dev/activation-apps.yaml` and `activation-environments.yaml` list element `env` | Both current generators receive the same explicit list. |
| `activation_server` | The same two list elements' `server` | Current per-cluster ArgoCD uses `https://kubernetes.default.svc`; do not substitute the raw EKS endpoint. |
| `namespace` | Contract assertion only | Current ApplicationSets derive `microtodo-{{ .env }}`; namespace is not a registration input. |
| `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_name` | Operator kubeconfig and constitution-approved one-time ArgoCD/root bootstrap | These do not flow into current activation patches. |
| `ecr_repository_urls[service]` | `apps/<service>/overlays/dev/kustomization.yaml` image `newName` | GitOps supplies `newTag` as `sha256:<digest>`; Terraform never chooses it. |
| `aws_region`, OIDC values, `irsa_role_arns` | AWS registration/environment-owned ServiceAccounts, secret stores, issuers, or controller bindings | Shared `infrastructure/*` installation roots remain provider-neutral. |
| Karpenter subnet/security-group outputs | Later coordinated Terraform and GitOps Karpenter feature | No Karpenter installation is part of this registration. |

The later `clusters/eks-dev/registration.yaml` still contains Git-reviewed:

```yaml
data:
  repoURL: <reviewed Git repository URL>
  revision: <reviewed branch, tag, or commit>
```

These two values are not Terraform outputs. The later root consumes
`../base`, and the one-time bootstrap installs only ArgoCD and its root
Application before GitOps assumes control.

## Image identity contract

Terraform returns repository locations, not deployable image identities. Build
and promotion automation must resolve the OCI manifest digest and the dev
overlay must pin that digest. A matching ECR/ACR tag is not evidence that two
registries contain the same artifact.

The known diagram edge from `todos-api` to `users-api` is also excluded from
this handoff: it has no bearing on foundation outputs, and the supplied domain
correction says Todos depends only on Redis.

## Provider-specific registration boundary

AWS-specific External Secrets stores, certificate issuer inputs, ingress
bindings, and service-account annotations belong in `clusters/eks-dev` or the
dev environment overlay. They must consume exact Terraform-created values and
must not fork or edit the provider-neutral add-on installation directories.

Terraform may create an IAM role only after its exact namespace, service
account, and policy are approved. GitOps then annotates that exact service
account; neither side uses wildcard subjects or static credentials.

## Known GitOps gaps that block literal value-only registration

The foundation output shape already fits the intended seam, but the current
GitOps checkout cannot register EKS literally by changing values alone:

1. `clusters/local-kind/kustomization.yaml` owns about 65 lines of replacement
   wiring for registration and activation. A sibling must copy that wiring or
   GitOps must extract it into reusable base behavior.
2. The future-EKS `tests/conformance/cluster-contract.sh` and fixtures referenced
   in `specs/001-local-gitops-pilot/checklists/acceptance.md` are still open.

The central-versus-per-cluster documentation conflict and the stale four-root
inventory were corrected during this implementation: every cluster owns its
ArgoCD reconciler and targets `https://kubernetes.default.svc`, and discovery
contains four controller add-ons plus Redis. The foundation follows that
implemented behavior and publishes both bootstrap and activation values so
Terraform will not need redesign. Reusable replacement extraction and the
future-EKS conformance fixture remain separate GitOps work.

## Acceptance checks

- The handoff object contains all schema fields and no credentials.
- `environment`, derived namespace, and activation server have the exact values
  above.
- ECR keys equal the five-service set and repository URLs are environment
  qualified.
- Raw EKS endpoint/CA are documented only for operator/bootstrap use.
- No output claims to supply `repoURL`, `revision`, or an image digest.
- No Terraform resource or wrapper writes GitOps files or invokes `kubectl`.
- The four current GitOps gaps remain visible in generated implementation and
  handoff documentation until the sibling repository resolves them.
