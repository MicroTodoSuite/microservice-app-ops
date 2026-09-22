#!/usr/bin/env bash
# Offline contract for the scheduled S3-to-Azure state replication workflow.
# The repository executes workflow contracts directly as Bash; the .bats suffix
# is retained for consistency with tests/workflows/foundation-checks.bats.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/eco-state-replication.yml"
failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

require_pattern() {
  local pattern=$1 message=$2
  if grep -Eq -- "$pattern" <<<"$workflow_code"; then
    pass "$message"
  else
    fail "$message"
  fi
}

reject_pattern() {
  local pattern=$1 message=$2
  if grep -Eq -- "$pattern" <<<"$workflow_code"; then
    fail "$message"
  else
    pass "$message"
  fi
}

if [[ ! -f "$WORKFLOW" ]]; then
  fail ".github/workflows/eco-state-replication.yml is missing"
  workflow_code=""
else
  workflow_code="$(sed -E -e 's/[[:space:]]*#.*$//' "$WORKFLOW")"
fi

require_pattern "cron:[[:space:]]*['\"]0 \*/6 \* \* \*['\"]" "the workflow runs every six hours"
require_pattern '^[[:space:]]*workflow_dispatch:' "the workflow supports manual dispatch"
reject_pattern '^[[:space:]]*(push|pull_request):' "the workflow does not run on push or pull request"

require_pattern 'contents:[[:space:]]*read' "the workflow grants contents read"
require_pattern 'id-token:[[:space:]]*write' "the workflow grants OIDC token minting"
reject_pattern '(^|[^a-z-])(access-key|secret-access-key|client-secret|sas-token|account-key)[[:space:]]*:' "the workflow contains no static cloud credential input"
require_pattern 'aws-actions/configure-aws-credentials@[0-9a-f]{40}' "the AWS OIDC login action is pinned by full commit SHA"
require_pattern 'azure/login@[0-9a-f]{40}' "the Azure OIDC login action is pinned by full commit SHA"
require_pattern 'role-to-assume:.*lex-mts-shd-role-tfstaterep' "the workflow assumes only the state-replication AWS role"
require_pattern 'client-id:.*vars\.AZURE_CLIENT_ID' "the Azure client ID comes from repository variables"
require_pattern 'tenant-id:.*vars\.AZURE_TENANT_ID' "the Azure tenant ID comes from repository variables"
require_pattern 'subscription-id:.*vars\.AZURE_SUBSCRIPTION_ID' "the Azure subscription ID comes from repository variables"

require_pattern 'environment:[[:space:]]*offsite-backups' "the job uses the protected offsite-backups environment"
require_pattern 'group:.*eco-state-replication' "the workflow serializes state-replication runs"
require_pattern 'cancel-in-progress:[[:space:]]*false' "an active state copy is never cancelled"

require_pattern 'eco/' "the workflow copies the eco state prefix"
require_pattern 'shd/' "the workflow copies the shd state prefix"
require_pattern '\*\.tflock' "the workflow excludes native S3 lock files"
require_pattern 'tfstate-replicas' "the workflow writes only to the state-replica container"
require_pattern 's3api[[:space:]]+list-object-versions' "the manifest reads source S3 version IDs"

require_pattern 'manifests/' "the workflow uploads a timestamped integrity manifest"
require_pattern '(version_id|versionId|VersionId)' "the manifest records each S3 version ID"
require_pattern '(size|Size)' "the manifest records each object size"
require_pattern '(sha256|SHA-256|sha256sum)' "the workflow computes SHA-256 values"
require_pattern 'az[[:space:]]+storage[[:space:]]+blob[[:space:]]+download' "the workflow downloads copied blobs for read-back verification"
require_pattern '--auth-mode[[:space:]]+login' "Azure Blob operations use the OIDC-backed login"

reject_pattern 'terraform[[:space:]]+(init|plan|apply|destroy)' "the copy workflow never runs Terraform"
reject_pattern 'aws[[:space:]]+s3[[:space:]]+(rm|sync)' "the copy workflow never runs a destructive S3 command"
reject_pattern 'az[[:space:]]+storage[[:space:]]+blob[[:space:]]+delete' "the copy workflow never deletes an Azure blob"
reject_pattern '--delete-destination' "the copy workflow never synchronizes deletions"

if [[ "$failures" -gt 0 ]]; then
  printf 'FAIL: %d state-replication workflow contract violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: the economical state-replication workflow contract holds\n'
