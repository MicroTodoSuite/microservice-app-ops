# microservice-app-ops

Terraform roots and lifecycle tooling for the MicroTodoSuite AWS environments.
This repository owns the Terraform state backend, the environment foundations
(VPC, EKS, IAM and IRSA, ECR, Secrets Manager, Route 53), and the centralized
egress hub. It contains no application runtime: Kubernetes workloads and
platform add-ons are delivered through
[`microservice-app-gitops`](https://github.com/MicroTodoSuite/microservice-app-gitops)
and ArgoCD.

## Layout

```
aws/environments/dev/backend/        S3 bucket and KMS key for Terraform state
aws/environments/<env>/foundation/   One root per environment, each with its own state key
aws/shared/egress/                   Centralized egress: Transit Gateway, one NAT gateway
aws/modules/                         Modules used by the roots, with Terraform tests
config/aws-account.env               The single declaration of the AWS account
scripts/                             Environment lifecycle, account change, preflight
tests/                               Contract, preflight, and workflow tests
specs/                               Spec Kit specifications, plans, and task registers
docs/aws-profile-lifecycle.md        The lifecycle runbook
```

The layout is being restructured into `aws/environments/{shd,eco,fdev,fstg,fprd}/`
roots split by domain (networking, security, workload) that consume versioned
modules from
[`terraform-aws-modules`](https://github.com/MicroTodoSuite/terraform-aws-modules).
The governance and IaC program in `microservice-app-ai-agents` tracks that work.

## Environment lifecycle

The `Makefile` is the operator interface. Every target that depends on a
profile requires `PROFILE=economical` or `PROFILE=full`; there is no default.

| Target | Effect |
| --- | --- |
| `make check`, `make init`, `make status` | Read-only preflight, initialization, and status |
| `make plan-up` | Saves the plans that bring a profile up |
| `make plan-down GITOPS_REVISION=<commit>` | Saves the plans that bring a profile down, after GitOps quiescence |
| `make inspect BUNDLE=<directory>` | Shows a saved plan bundle for review |
| `make apply-up BUNDLE=<directory>`, `make apply-down BUNDLE=<directory>` | Applies a reviewed bundle |

Bringing a profile down removes the runtime — VPCs, NAT gateways, EKS clusters
and node groups, and cluster-scoped identities — and preserves the durable
assets: the state backend, ECR images, secrets, hosted zones, and the GitHub
OIDC trust. [`docs/aws-profile-lifecycle.md`](docs/aws-profile-lifecycle.md) is
the runbook.

## Rules that govern changes

- **Saved plans only.** An apply uses only an approved saved plan, after a
  timestamped external state backup, or a `no-prior-state` receipt for a
  genuinely new state key.
- **One account declaration.** The AWS account is declared once in
  `config/aws-account.env` and changed only with
  `scripts/set-aws-account.sh <account-id>`. A contract test fails on any other
  account literal that is not listed, with its reason, in
  `config/aws-account-exceptions.txt`.
- **Documentation servers first.** Infrastructure changes require the
  documentation MCP servers in `.mcp.json`, verified with
  `microservice-app-ai-agents/scripts/check-mcp.sh terraform-aws .`, and every
  pull request lists the documentation consulted.
- **Distinct state keys.** Every environment is a separate root with its own key
  in the shared bucket; `aws-full-foundation-checks.yml` verifies that no two
  roots share one.
- **Delivery conventions.** Branches, commits, pull requests, and task tracking
  follow the
  [conventions](https://github.com/MicroTodoSuite/microservice-app-docs/blob/main/docs/Pull%20request%20and%20task%20tracking%20conventions.md).
  The IaC rules are in `microservice-app-ai-agents/rules/iac/`.

## Checks and releases

| Workflow | Runs |
| --- | --- |
| `aws-dev-foundation-checks.yml` | Formatting, validation, and Terraform tests for the economical root and the environment-foundation module, plus the lifecycle, account, and foundation contract tests |
| `aws-full-foundation-checks.yml` | Formatting, validation, and tests for each full-profile root and the egress hub, the state-key uniqueness check, and an Infracost estimate when an API key is configured |
| `release.yml` | semantic-release on `main`: version, tag, and changelog |
