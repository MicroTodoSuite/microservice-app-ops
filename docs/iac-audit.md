# Infrastructure-as-Code Audit

**Date**: 2026-09-12
**Task**: `microservice-app-ai-agents` specs/001-governance-and-iac-program T021
**Subjects**: `microservice-app-ops` at `658b84f`; `microservice-app-gitops` at
`15faeee` for the rules that apply to it (MTS-IAC-103, 105, 106)
**Rules**: `microservice-app-ai-agents/rules/iac/` at `2b04bc6`, with the
adaptations proposed in microservice-app-ai-agents#12
**Checks**: the rule contracts of MicroTodoSuite/.github#17 at `27a9df9`

## Reading this register

The code in this repository predates the IaC rules, so nearly every finding is
structural. Findings of that kind are removed by rebuilding, not by editing
today's files. The modules are rewritten as single-responsibility modules in
`terraform-aws-modules` (T023), the roots are rebuilt per environment and domain
(T025), and literal values move to environment `.tfvars` (T026). Every finding
below names the task that removes it. No finding is waived, and none is
suppressed. The raw output of every tool is in `docs/iac-audit/2026-09-12/`.

## Method

| Check | Tool | Scope |
| --- | --- | --- |
| Rule contracts | `scripts/iac/contracts.py` (python-hcl2 8.1.4), `repo . --kind live` and `module aws/modules/<name>` | 6 roots, 5 modules |
| Lint | tflint 0.64.0 with tflint-ruleset-aws 0.48.0 and the gate's default configuration, `--recursive` | The whole repository |
| Misconfiguration scan | Trivy 0.74.0, `trivy config --severity HIGH,CRITICAL aws/` | `aws/`, including the upstream modules the roots download |
| Rules without a contract | Reading the code, with AWS documentation consulted through the `aws-knowledge` MCP server | PC-IAC-009, 010, 011, 013, 014, 020, 021, 024 |
| Workflows and desired state | `git grep` over workflows and manifests | ops and gitops, MTS-IAC-105 and 106 |

## Summary

| Source | Findings | Removed by |
| --- | --- | --- |
| Contracts, six roots | 230 | T025, T026, T028 |
| Contracts, five modules | 328 | T023 |
| tflint | 14 warnings | T023, T025 |
| Trivy | 8 CRITICAL (2 checks, 4 roots) | T023 and the exceptions of T041 |
| Rules without a contract | 8 `depends_on` without a reason; literal CIDRs | T023, T025, T026 |
| GitHub Actions, ops | 9 action references by tag | T025 |
| Kubernetes desired state, gitops | 4 first-party images by tag | T042 |

## Contract findings

| Rule | Count | Finding | Removed by |
| --- | --- | --- | --- |
| MTS-IAC-102 | 5 | The five directories under `aws/modules/` are module copies inside a live repository | T023 moves them to `terraform-aws-modules`; T025 consumes them by tag |
| MTS-IAC-103 | 12 | `full-dev` and `full-prod` pin the retired account (`variables.tf:23–24`) and `us-east-1` (`:31`, `:34`) in variable validation; `shared/egress` does the same (`:12–13`, `:20`, `:23`) | T028 (decision 1) and T026 |
| PC-IAC-001 | 99 | Modules lack `README.md`, `CHANGELOG.md`, `locals.tf`, `data.tf`, or `sample/`; `environment-foundation` spreads its resources over fifteen additional files | T023 |
| PC-IAC-002 | 166 | Non-boolean variables without validation (78 in roots), defaults on inputs that identify or size infrastructure such as instance types, CIDRs, and zone names (49 in roots), and no `client`, `project`, or `environment` input (14 in roots) | T025, T023, and T026 for sizes |
| PC-IAC-003 | 2 | `state-backend` and `environment-foundation` have no principal resource named `this` | T023 |
| PC-IAC-004 | 3 | `centralized-egress`, `environment-foundation`, and `state-backend` accept no `additional_tags` | T023 |
| PC-IAC-005 | 103 | Six root providers lack the `principal` alias and `assume_role`; 85 module findings where resources and data sources do not use `aws.project` and three modules declare no `configuration_aliases` | T025, T023 |
| PC-IAC-006 | 18 | `required_version = "= 1.15.8"` in every root and module; lock files and exact provider pins committed inside modules | T023, T025 |
| PC-IAC-007 | 35 | Outputs named for what they describe rather than what they return (`environment`, `foundation_contract`, `values`, `egress_public_ips`) or returning whole objects | T023, T025 |
| PC-IAC-008 | 2 | `aws/environments/dev/backend` runs on local state; the rule allows that only for the state root, which T025 creates as `shd/state` | T025 |
| PC-IAC-010 | 5 | `aws_ecr_repository.services`, `.neutral_services`, `.platform_mirror`, and `aws_route53_zone.public` and `.canonical` lack `prevent_destroy` | T023 (`ecr-repository`, `route53-zone`), T029 recreates them under `lex-mts` names |
| PC-IAC-011 | 10 | `environment-foundation` looks up existing roles, repositories, secrets, and the GitHub OIDC provider in order to adopt them | T025 moves lookups to roots; T029 replaces adoption with imports |
| PC-IAC-012 | 29 | 23 `locals` blocks outside `locals.tf`; no root defines `governance_prefix` | T023, T025 |
| PC-IAC-015 | 9 | Roots call modules by local path | T025 |
| PC-IAC-016 | 4 | `dr_secret_seed_subjects` and `dr_secret_seed_workflow_refs`, in `dev/foundation` and `environment-foundation`, match the secret-name heuristic. They hold OIDC subjects, not secrets; the new roots name them without "secret" rather than mark them sensitive | T025 |
| PC-IAC-018 | 3 | `environment-jwt-values`, `ephemeral-passwords`, and `state-backend` have no `terraform test` | T023 |
| PC-IAC-022 | 6 | No root is split by domain | T025 |
| PC-IAC-023 | 28 | `environment-foundation` creates 27 IAM, security-group, and routing resources; `centralized-egress` creates a route | T023 decomposes both |
| PC-IAC-025 | 19 | Modules assemble names from governance variables (`environment-foundation` 16, `state-backend` 3) | T023, T025 |

Running the contracts here also exposed two false positives in the contracts
themselves: boolean switches and identifiers of secrets were flagged as secrets,
and the state root's local backend was flagged. Both were corrected in
MicroTodoSuite/.github#17, test first, before these counts were taken.

## tflint

| Rule | Count | Removed by |
| --- | --- | --- |
| `terraform_standard_module_structure` | 7 | T023 |
| `terraform_unused_declarations` | 5 | T023, T025 |
| `terraform_required_version` | 2 | T025 |

All fourteen are warnings. The gate fails on warnings, so the rewritten code
starts clean.

## Trivy

Both checks fire inside the upstream `terraform-aws-modules/eks/aws` module, once
for each of the four EKS roots (`dev`, `demo-full`, `full-dev`, `full-prod`).

| Check | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| AWS-0040 | CRITICAL | EKS clusters should have public access disabled | See below |
| AWS-0104 | CRITICAL | A security group rule should not allow unrestricted egress to any IP address | See below |

**AWS-0040.** The clusters set `endpoint_public_access = true`, with the allowed
CIDRs taken from `var.cluster_public_access_cidrs`. AWS documentation, consulted
through the `aws-knowledge` MCP server, says to restrict the endpoint "to only
necessary IP ranges" (Security Hub, *Remediating exposures for Amazon EKS
clusters*). The EKS best-practices guide lists three options: a private
endpoint, a public endpoint with allow-listed CIDRs, or both together, which
keeps node traffic private (*Identity and Access Management*). The
`eks-cluster` module (T023) will always enable private access and make public
access opt-in with a required CIDR list. `fstg` and `fprd` stay private-only,
as PC-IAC-020 requires. The economical cluster's public endpoint is a recorded
development trade-off (ops spec 001), and it continues only if the team records
an exception with an expiry in its own reviewed change (T041).

**AWS-0104.** The node security group allows all outbound traffic. AWS's own
guidance for EKS is "to allow all traffic to flow between your cluster and nodes
and allow all outbound traffic to any destination" (AWS re:Post, *Why am I unable
to connect from Amazon EKS to other AWS services?*, citing *Amazon EKS security
group requirements*). Nodes reach ECR, S3, STS, and CloudWatch Logs through that
egress; restricting it requires VPC endpoints, which are billed by the hour. The
`security-group` module (T023) will express node egress as an explicit rule, and
the finding needs a team exception with an expiry tied to budgeting those
endpoints (T041).

This audit suppresses neither finding. Under the conventions, a suppression is a
team decision in its own reviewed change.

## Rules reviewed by reading

| Rule | Result | Removed by |
| --- | --- | --- |
| PC-IAC-009 | No module call contains a `for` expression or a `merge()` over a data source | — |
| PC-IAC-010 | Eight `depends_on` without a comment naming the dependency Terraform cannot see: `modules/state-backend/main.tf:102`, `modules/centralized-egress/main.tf:232`, `modules/environment-foundation/eks.tf:100`, `:184`, `:208`, `:227`, `:247`, `environments/dev/backend/main.tf:11`. Only `eks.tf:63` explains itself. No `ignore_changes`; `count` appears only as a zero-or-one condition | T023, T025 |
| PC-IAC-011 | The two `[0]` references (`managed-secrets.tf:152`, `karpenter.tf:118`) index the count instance of a conditional data source, not a list result; not a violation | — |
| PC-IAC-013, 014, 021 | No dynamic blocks, no disordered module calls, no configuration outside locals found | — |
| PC-IAC-020 | KMS rotation on the state, flow-log, and Karpenter keys; the state bucket blocks public access and sets `force_destroy = false`; ECR tags are immutable and scanned on push; flow logs and EBS volumes are encrypted. The endpoint and egress findings are Trivy's, above | T041 |
| PC-IAC-024 | CIDRs appear as variable defaults and validation pins: `shared/egress/variables.tf:31`, `:43`, `:49`, `:68–70`; `full-dev/foundation/variables.tf:54`, `:57`, `:71`, `:77`, and the same in `full-prod` | T026 |

## GitHub Actions (MTS-IAC-106)

**ops.** Nine action references use a tag instead of a commit SHA:
- `aws-dev-foundation-checks.yml`:
  - `:38` — `actions/checkout@v4`
  - `:41` — `hashicorp/setup-terraform@v3`
- `aws-full-foundation-checks.yml`:
  - `:48`, `:86`, `:116` — `actions/checkout@v4`
  - `:51` — `hashicorp/setup-terraform@v3`
  - `:130` — `infracost/actions/setup@v3`
- `release.yml`:
  - `:21` — `actions/checkout@v4`
  - `:26` — `actions/setup-node@v4`

All four workflows declare top-level `permissions`. T025 replaces the two check
workflows with a caller of the reusable `iac-checks` gate and pins
`release.yml` in the same change.

**gitops.** `validate-gitops.yml` pins every action by SHA and declares its
permissions.

## Kubernetes desired state (MTS-IAC-105)

- The five services' base manifests carry placeholder image names. Every
  overlay replaces them with a digest through kustomize: 37 digest entries and no
  tags.
- The vendored upstream manifests under `infrastructure/*/vendor/<version>/` and
  `bootstrap/argocd/vendor/` carry `SHA256SUMS`. The tags inside them are
  upstream's, pinned by checksum, which the rule allows.
- Four first-party manifests reference images by tag:
  - `infrastructure/keda/capability-check.yaml:25` — `registry.k8s.io/pause:3.10.1`
  - `infrastructure/sonarqube/postgres.yaml:57` — `postgres:16-alpine`
  - `infrastructure/sonarqube/sonarqube.yaml:74` — `busybox:1.37`
  - `infrastructure/sonarqube/sonarqube.yaml:83` — `sonarqube:community`

  They are removed by T042, with the SonarQube images coordinated with the open
  SonarQube hardening pull request, gitops#118.
- The account parameter (MTS-IAC-103) in gitops is enforced by the repository's
  own `tests/contract/aws-account-parameter.sh`.

## Tasks this audit adds

The paired pull request in `microservice-app-ai-agents` adds these tasks to the
program register:

- **T041 GOV**: decide and record, each in its own reviewed change and with an
  expiry, whether Trivy AWS-0040 (the economical cluster's public endpoint) and
  AWS-0104 (node egress) become exceptions.
- **T042 INF**: pin the four first-party gitops images by digest.

## Evidence

| File | Content |
| --- | --- |
| `docs/iac-audit/2026-09-12/contracts-live.json` | Contract findings for the six roots |
| `docs/iac-audit/2026-09-12/contracts-module-<name>.json` | Contract findings for each module |
| `docs/iac-audit/2026-09-12/tflint.json` | tflint issues |
| `docs/iac-audit/2026-09-12/trivy.json` | Trivy misconfigurations |
