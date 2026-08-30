## Overview
This repository provisions and operates the Azure infrastructure for MicroTodoSuite through Terraform and GitHub Actions.
It creates the Terraform state backend, shared Azure Container Apps resources, ten container apps, and deployment, restart, and release automation; it contains no application runtime.

## Stack
- Infrastructure: Terraform HCL. Backend and base-infrastructure CI jobs pin Terraform 1.5.0; container-app and destroy jobs request `latest`.
- Providers: AzureRM and Random. No `required_providers`, provider version constraint, `required_version`, or committed `.terraform.lock.hcl` exists.
- Automation: GitHub Actions, Bash, Azure CLI, GitHub CLI, and curl; their CLI versions are not pinned.
- Release tooling: Node.js 22 with semantic-release 24.2.3, @semantic-release/changelog 6.0.3, and @semantic-release/git 10.0.1 from `package-lock.json`.

## Commands
- Install the release dependencies: `npm ci`.
- Run the release automation: `npx semantic-release` (the workflow supplies `GITHUB_TOKEN`).
- Initialize and validate a Terraform root: `terraform init`, then `terraform validate`; CI runs these in `backend/`, `base-infrastructure/`, and `container-apps/`, with backend arguments for the latter two.
- Apply the saved backend/base plan: `terraform apply -input=false tfplan`; apply the container plan: `terraform apply -input=false tfplan-containers`.
- `npm test` is the only declared test command; it prints `Error: no test specified` and exits with status 1. There are no test files, build command, or local-run command.

## Structure
- `backend/`: creates the Azure resource group, storage account, and private blob container used for Terraform state.
- `base-infrastructure/`: remote-state Terraform root for the resource group, Azure Container Registry, Log Analytics workspace, and Container Apps environment.
- `base-infrastructure/modules/`: local modules for the resource group, registry, and Container Apps environment.
- `container-apps/`: remote-state Terraform root defining Redis, Zipkin, users-api, auth-api, todos-api, log-message-processor, frontend, frontend-exporter, Prometheus, and Grafana.
- `container-apps/modules/container_apps/`: reusable Azure Container App module for ingress, scaling, registry credentials, environment variables, secrets, and command overrides.
- `.github/workflows/`: backend setup, infrastructure deployment/destruction, ordered restarts, resiliency configuration, and semantic-release workflows.
- `scripts/setup-azure-secrets.sh`: writes infrastructure values to this repository and six microservice repositories with GitHub CLI.
- `package.json`, `package-lock.json`, and `.releaserc`: release-only Node dependencies and semantic-release configuration.

## Conventions
- Treat `backend/`, `base-infrastructure/`, and `container-apps/` as independent Terraform roots; base and container state use separate Azure Blob keys.
- Container environment values beginning with `secretref:` are converted by the local module into Azure Container App secret references.
- Use short-lived branches merged into `main`. Kubernetes environment changes must go through commits to `microservice-app-gitops` and ArgoCD; never run `kubectl apply` against a GitOps-managed cluster.
- Write pull-request bodies bilingually: every section in English, then repeated under a `## Español` heading with the same content, not a summary. Titles, commits, code comments, documentation, and specification text stay English-only. As an AI agent you write both halves yourself.
- Open every pull request through `.github/pull_request_template.md` and follow `microservice-app-docs/docs/Pull request and task tracking conventions.md`: one concern per short-lived `<type>/<summary>` branch, a Conventional Commit title with a scope, and every template section filled. Constitution principle 13 makes this binding, not advisory.
- Keep the Spec-Driven Development commit pair intact: `test(<scope>): specify ...` must be committed failing before `feat(<scope>): implement ...`. Never squash the pair; the failing-test commit is the evidence the cycle was followed.
- Track every task. Name in the pull-request body the task IDs it advances, qualified by repository and spec, and update `tasks.md` in that same pull request rather than a follow-up. Mark a task `[X]` only after locating and inspecting its named artifact — never from a summary, a green check, a rendered manifest, or recollection. Annotate partial delivery instead of ticking it; work no register covers either gains a task or records in the PR body why none applies.
- Reconcile, never quietly edit, when a register and reality disagree: a specification that pins a version nobody shipped is a maintainer decision, and `microservice-app-docs/full-platform/plan-reconciliation.md` is the worked example.
- Never merge with `--admin`, force-push to `main`, disable a branch protection rule to land your own work, or approve your own pull request. As an AI agent you may open, describe, and update a pull request; you may never approve one and never author an acceptance or approval artifact — only a named human unlocks a gate.
- Report outcomes faithfully in commits and pull-request bodies: name what is red, say what was skipped, and correct an earlier claim that turns out to be wrong rather than leaving the record wrong.

## Notes for the Kubernetes migration
- Ports/exposure: external—Zipkin 9411, frontend 8080, Prometheus 9090, Grafana 3000; internal—Redis 6379/TCP, users-api 8083, auth-api 8000, todos-api 8082, log-message-processor 8081, frontend-exporter 9113.
- users-api variables: `JWT_SECRET`, `SERVER_PORT=8083`, `SPRING_PROFILES_ACTIVE=default`, `ZIPKIN_URL=http://zipkin/`.
- auth-api variables: `JWT_SECRET`, `AUTH_API_PORT=8000`, `USERS_API_ADDRESS=http://users-api`, `ZIPKIN_URL=http://zipkin/api/v2/spans`.
- todos-api variables: `TODO_API_PORT=8082`, `REDIS_HOST=redis`, `REDIS_PORT=6379`, `REDIS_CHANNEL=log_channel`, `USERS_API_URL=http://users-api`, `ZIPKIN_URL`, and `JWT_SECRET`.
- log-message-processor variables: `PORT=8081`, `REDIS_HOST`, `REDIS_PORT`, `REDIS_CHANNEL`, and `ZIPKIN_URL`; frontend uses `PORT=8080`, `AUTH_API_ADDRESS`, `TODOS_API_ADDRESS`, `ZIPKIN_URL`, and `JWT_SECRET`.
- Prometheus needs `AUTH_API_TARGET`, `USERS_API_TARGET`, `TODOS_API_TARGET`, `LOG_PROCESSOR_TARGET`, and `FRONTEND_EXPORTER_TARGET`; Grafana sets `GF_SECURITY_ADMIN_PASSWORD` and `GF_PATHS_PROVISIONING`.
- Service dependencies use bare-name HTTP endpoints for Zipkin, users-api, auth-api, and todos-api; Redis pub/sub uses `log_channel`. No database is declared. The exporter scrapes `http://frontend/nginx_status`.
- External platform dependencies are Azure Blob state, Azure Container Registry, Container Apps, Log Analytics, GitHub APIs/repositories, and Docker Hub images for Zipkin, Redis, nginx-prometheus-exporter, and Grafana.
- CI identity/state inputs are `AZURE_CREDENTIALS_COLONIA`, `AZURE_SUBSCRIPTION_ID_COLONIA`, `GH_TOKEN`, `TF_STATE_RESOURCE_GROUP`, `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER`, `TF_STATE_ACCESS_KEY`, `TF_STATE_BASE_INFRASTRUCTURE_KEY`, `TF_STATE_CONTAINER_APPS_KEY`, and `TF_STATE_KEY`.
- Other CI inputs are `AZURE_LOCATION`, `AZURE_RESOURCE_GROUP_NAME`, `ACR_NAME`, `ACR_SKU`, `ACR_ADMIN_ENABLED`, `CONTAINER_APPS_ENVIRONMENT_NAME`, `JWT_SECRET`, and `STANDARD_TAGS`.
- No Dockerfile exists. Review all `:latest` image tags, ACR admin credentials, hard-coded JWT/Grafana defaults, Redis without persistent storage, public monitoring ingress, and the absence of health probes and volumes.
- The destroy workflow targets an absent `terraform/` directory and uses `TF_STATE_KEY`; resolve that stale path/key rather than carrying it into the migration.
- Current workflows apply Terraform and mutate Container Apps through Azure CLI. Kubernetes changes must instead be committed to `microservice-app-gitops` for ArgoCD reconciliation in the single AWS account, with environments isolated by clusters/VPCs or namespaces.
- Translate Azure single-revision mode, 1–3 replica limits, ingress transport, secret references, registry authentication, and CLI-created resiliency policies into GitOps-managed Kubernetes Deployments, Services, Ingress/NetworkPolicies, Secrets, storage, probes, and scaling policies.
