#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTRYPOINT="$ROOT/scripts/aws-profile-lifecycle.sh"
DURABLE_DELETE_FILTER="$ROOT/scripts/aws-profile-durable-deletes.jq"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "missing file: $1"
}

require_text() {
  local file=$1
  shift
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  local pattern=$1
  local message=$2
  grep -Eq -- "$pattern" "$ROOT/$file" || fail "$message"
}

reject_text() {
  local file=$1
  shift
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  local pattern=$1
  local message=$2
  if grep -En -- "$pattern" "$ROOT/$file" >/dev/null; then
    fail "$message"
  fi
}

require_file "scripts/aws-profile-lifecycle.sh"
require_file "scripts/aws-profile-durable-deletes.jq"
require_file "docs/aws-profile-lifecycle.md"
require_file ".github/workflows/aws-dev-foundation-checks.yml"

[[ -x "$ENTRYPOINT" ]] || fail "scripts/aws-profile-lifecycle.sh is not executable"

for profile in economical full; do
  require_text "scripts/aws-profile-lifecycle.sh" "(^|[^a-z])${profile}([^a-z]|$)" \
    "wrapper is missing the ${profile} profile"
done

for direction in up down; do
  require_text "scripts/aws-profile-lifecycle.sh" "(^|[^a-z])${direction}([^a-z]|$)" \
    "wrapper is missing the ${direction} direction"
done

for command in check init plan inspect apply status; do
  require_text "scripts/aws-profile-lifecycle.sh" "^[[:space:]]*${command}\)" \
    "wrapper is missing the ${command} command"
done

require_text "scripts/aws-profile-lifecycle.sh" 'terraform[[:space:]]+-chdir=' \
  "wrapper must isolate every Terraform invocation with -chdir"
require_text "scripts/aws-profile-lifecycle.sh" -- '-input=false' \
  "wrapper must disable interactive Terraform input"
require_text "scripts/aws-profile-lifecycle.sh" -- '-lock-timeout=5m' \
  "wrapper plans must use the bounded state-lock timeout"
require_text "scripts/aws-profile-lifecycle.sh" -- '-out=' \
  "wrapper must save plans before apply"
require_text "scripts/aws-profile-lifecycle.sh" 'sha256sum' \
  "wrapper must checksum saved plans"
require_text "scripts/aws-profile-lifecycle.sh" 'gitops[_-]revision' \
  "wrapper must record GitOps quiescence evidence"
require_text "scripts/aws-profile-lifecycle.sh" 'get-caller-identity' \
  "wrapper must verify the active AWS identity"
require_text "scripts/aws-profile-lifecycle.sh" 'runtime_enabled=false' \
  "foundation shutdown must use the runtime boundary"
require_text "scripts/aws-profile-lifecycle.sh" 'plan[[:space:]]+-destroy' \
  "full shutdown must plan destruction of the ephemeral egress root"
require_text "scripts/aws-profile-lifecycle.sh" 'require_command[[:space:]]+grep' \
  "wrapper must preflight its portable grep dependency"
require_text "scripts/aws-profile-lifecycle.sh" 'grep[[:space:]]+-Eq' \
  "wrapper state checks must use portable extended grep"
reject_text "scripts/aws-profile-lifecycle.sh" '(^|[[:space:]])rg([[:space:]]|$)' \
  "wrapper must not require ripgrep for operator commands"
reject_text "scripts/aws-profile-lifecycle.sh" 'auto-approve|kubectl[[:space:]]+(apply|delete|patch|scale)' \
  "wrapper must not auto-approve Terraform or mutate GitOps-managed clusters"
require_text "scripts/aws-profile-lifecycle.sh" 'jq[[:space:]]+-r[[:space:]]+-f[[:space:]]+"\$DURABLE_DELETE_FILTER"' \
  "wrapper must audit shutdown plans with the versioned durable-delete filter"
require_text ".github/workflows/aws-dev-foundation-checks.yml" "scripts/aws-profile-durable-deletes\\.jq" \
  "AWS foundation workflow must run when the durable-delete filter changes"

runtime_oidc_plan="$(jq -n '
  {
    resource_changes: [{
      address: "module.foundation.module.eks[0].aws_iam_openid_connect_provider.oidc_provider[0]",
      type: "aws_iam_openid_connect_provider",
      change: {
        actions: ["delete"],
        before: {url: "oidc.eks.us-east-1.amazonaws.com/id/example"}
      }
    }]
  }
')"
runtime_oidc_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$runtime_oidc_plan")"
[[ -z "$runtime_oidc_deleted" ]] || \
  fail "the cluster-scoped EKS OIDC provider must be removable with the runtime"

github_oidc_plan="$(jq -n '
  {
    resource_changes: [{
      address: "module.foundation.aws_iam_openid_connect_provider.github_actions[0]",
      type: "aws_iam_openid_connect_provider",
      change: {
        actions: ["delete"],
        before: {url: "token.actions.githubusercontent.com"}
      }
    }]
  }
')"
github_oidc_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$github_oidc_plan")"
[[ "$github_oidc_deleted" == "module.foundation.aws_iam_openid_connect_provider.github_actions[0]" ]] || \
  fail "the account-level GitHub Actions OIDC provider must remain protected"

ecr_plan="$(jq -n '
  {
    resource_changes: [{
      address: "module.foundation.aws_ecr_repository.services[\"auth-api\"]",
      type: "aws_ecr_repository",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
ecr_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$ecr_plan")"
[[ "$ecr_deleted" == 'module.foundation.aws_ecr_repository.services["auth-api"]' ]] || \
  fail "durable ECR repositories must remain protected"

for root in dev demo-full full-dev full-prod; do
  require_text "aws/environments/${root}/foundation/variables.tf" 'variable "runtime_enabled"' \
    "${root} root is missing runtime_enabled"
  require_text "aws/environments/${root}/foundation/main.tf" 'runtime_enabled[[:space:]]*=[[:space:]]*var\.runtime_enabled' \
    "${root} root does not pass runtime_enabled to the foundation module"
done

require_text "aws/modules/environment-foundation/variables.tf" 'variable "runtime_enabled"' \
  "foundation module is missing runtime_enabled"
require_text "aws/modules/environment-foundation/variables.tf" 'default[[:space:]]*=[[:space:]]*true' \
  "runtime_enabled must default on"
require_text "aws/modules/environment-foundation/outputs.tf" 'runtime_enabled[[:space:]]*=[[:space:]]*var\.runtime_enabled' \
  "foundation contract does not expose runtime state"

for durable_file in ecr.tf route53.tf github-oidc.tf; do
  reject_text "aws/modules/environment-foundation/${durable_file}" \
    '(count|for_each)[[:space:]]*=[^\n]*runtime_enabled' \
    "durable resources in ${durable_file} must not depend on runtime_enabled"
done
require_text "aws/modules/environment-foundation/managed-secrets.tf" \
  'resource "aws_secretsmanager_secret" "environment_jwt"' \
  "durable environment JWT secret containers are missing"
require_text "aws/modules/environment-foundation/managed-secrets.tf" \
  'resource "aws_secretsmanager_secret_version" "environment_jwt"' \
  "durable environment JWT secret values are missing"

printf 'PASS: AWS profile lifecycle contract\n'
