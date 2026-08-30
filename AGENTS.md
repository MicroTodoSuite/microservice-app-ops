## Overview
This repository provisions the AWS infrastructure for MicroTodoSuite through Terraform and GitHub Actions.
It owns the S3/KMS state backend, the shared environment-foundation module (VPC, EKS, IAM/IRSA, ECR, Secrets Manager), the centralized-egress hub, and one Terraform root per environment; it contains no application runtime.

The Azure Container Apps estate this repository used to operate was retired on 2026-08-30. Kubernetes workloads are delivered through `microservice-app-gitops` and ArgoCD, never from here.

## Stack
- Infrastructure: Terraform HCL with the AWS provider.
- Automation: GitHub Actions, Bash, AWS CLI, GitHub CLI, and Infracost.
- Release tooling: Node.js with semantic-release, from `package-lock.json`.

## Commands
- Install the release dependencies: `npm ci`.
- Run the release automation: `npx semantic-release` (the workflow supplies `GITHUB_TOKEN`).
- Initialize and validate a Terraform root: `terraform init -backend-config=<root>.s3.tfbackend`, then `terraform validate`.
- Run a module's tests: `terraform test` inside the module directory.
- Apply only a reviewed saved plan: `terraform apply -input=false <plan>`; never a convenience apply.
- `npm test` is the only declared test command and it is a placeholder.

## Structure
- `aws/environments/dev/backend/`: bootstraps the S3 bucket and KMS key used for Terraform state.
- `aws/environments/{dev,demo-full,full-dev,full-prod}/foundation/`: one remote-state root per environment, each with its own backend key.
- `aws/shared/egress/`: the centralized-egress root — one NAT gateway and Elastic IP behind a Transit Gateway.
- `aws/modules/environment-foundation/`: the shared VPC, EKS, IAM/IRSA, ECR, and Secrets Manager module, with its Terraform tests.
- `aws/modules/{centralized-egress,state-backend,environment-jwt-values,ephemeral-passwords}/`: the supporting modules.
- `scripts/preflight/azure-dr.sh`: read-only Azure discovery for the planned AKS disaster-recovery environment (spec 009 T124). This is the future multi-cloud leg, unrelated to the retired Container Apps estate.
- `tests/`: contract and preflight tests.
- `specs/`: the Spec Kit lifecycle for this repository.

## Conventions
- Treat `backend/`, `base-infrastructure/`, and `container-apps/` as independent Terraform roots; base and container state use separate Azure Blob keys.
- Container environment values beginning with `secretref:` are converted by the local module into Azure Container App secret references.
- Use short-lived branches merged into `main`. Kubernetes environment changes must go through commits to `microservice-app-gitops` and ArgoCD; never run `kubectl apply` against a GitOps-managed cluster.
- Write everything in English — branch names, commit messages, pull-request titles and bodies, review comments, code comments, documentation, and specification text. No bilingual sections. Changing this rule takes a recorded decision in `microservice-app-docs`, not a remark in conversation.
- Open every pull request through `.github/pull_request_template.md` and follow `microservice-app-docs/docs/Pull request and task tracking conventions.md`: one concern per short-lived `<type>/<summary>` branch, a Conventional Commit title with a scope, and every template section filled. Constitution principle 13 makes this binding, not advisory.
- Keep the Spec-Driven Development commit pair intact: `test(<scope>): specify ...` must be committed failing before `feat(<scope>): implement ...`. Never squash the pair; the failing-test commit is the evidence the cycle was followed.
- Track every task. Name in the pull-request body the task IDs it advances, qualified by repository and spec, and update `tasks.md` in that same pull request rather than a follow-up. Mark a task `[X]` only after locating and inspecting its named artifact — never from a summary, a green check, a rendered manifest, or recollection. Annotate partial delivery instead of ticking it; work no register covers either gains a task or records in the PR body why none applies.
- Reconcile, never quietly edit, when a register and reality disagree: a specification that pins a version nobody shipped is a maintainer decision, and `microservice-app-docs/full-platform/plan-reconciliation.md` is the worked example.
- Never merge with `--admin`, force-push to `main`, disable a branch protection rule to land your own work, or approve your own pull request. As an AI agent you may open, describe, and update a pull request; you may never approve one and never author an acceptance or approval artifact — only a named human unlocks a gate.
- Report outcomes faithfully in commits and pull-request bodies: name what is red, say what was skipped, and correct an earlier claim that turns out to be wrong rather than leaving the record wrong.

## Notes
- Every environment is a separate Terraform root with a distinct state key in the shared bucket. Two roots sharing a key destroys an environment rather than erroring, so the state-key uniqueness check in `aws-full-foundation-checks.yml` is load-bearing.
- State locking is Terraform's native S3 lockfile (`use_lockfile = true`). There is no DynamoDB lock table, by recorded decision in `specs/001-aws-dev-foundation/plan.md`.
- The economical dev environment is the live platform and the rollback target for the whole full-profile rollout. After any change under `aws/`, re-run the dev plan and confirm `0 to add, 0 to change, 0 to destroy` from the plan JSON — `terraform show -json`, every `resource_changes` entry `no-op` — not from the printed text. Every full-profile switch defaults off.
- Applies use only an approved saved plan after a timestamped external state backup under `~/backups-microtodosuite/`, or a `no-prior-state` receipt for a genuinely new key.
- The full-profile rollout is driven by `microservice-app-gitops/specs/009-full-platform-rollout/`. Its task register is the source of truth for what is done; `microservice-app-docs/full-platform/plan-reconciliation.md` reconciles it against reality.
- The planned Azure work is AKS for disaster recovery (spec 009 T118-T141), sequenced last. It is not a revival of Container Apps.
