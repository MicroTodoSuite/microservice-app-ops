#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FOUNDATION="$ROOT/aws/environments/dev/foundation"
MODULE="$ROOT/aws/modules/environment-foundation"
ENTRYPOINT="$ROOT/scripts/aws-dev-foundation.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "missing file: $1"
}

require_text() {
  local file=$1
  local pattern=$2
  local message=$3
  rg -q -- "$pattern" "$ROOT/$file" || fail "$message"
}

reject_text() {
  local path=$1
  local pattern=$2
  local message=$3
  if rg -n --glob '*.tf' --glob '*.sh' -- "$pattern" "$ROOT/$path" >/dev/null; then
    fail "$message"
  fi
}

require_file ".terraform-version"
require_file "aws/modules/environment-foundation/network.tf"
require_file "aws/modules/environment-foundation/eks.tf"
require_file "aws/modules/environment-foundation/ecr.tf"
require_file "aws/modules/environment-foundation/irsa.tf"
require_file "aws/modules/environment-foundation/outputs.tf"
require_file "aws/environments/dev/foundation/main.tf"
require_file "aws/environments/dev/foundation/dev.tfvars"
require_file "aws/environments/dev/foundation/dev.tfvars.example"
require_file "scripts/aws-dev-foundation.sh"

[[ -x "$ENTRYPOINT" ]] || fail "scripts/aws-dev-foundation.sh is not executable"
[[ "$(tr -d '[:space:]' <"$ROOT/.terraform-version")" == "1.15.8" ]] \
  || fail ".terraform-version is not pinned to 1.15.8"

for subcommand in check init validate test plan cost; do
  require_text "scripts/aws-dev-foundation.sh" "^[[:space:]]*$subcommand\\)" \
    "entrypoint is missing the $subcommand subcommand"
done

require_text "scripts/aws-dev-foundation.sh" 'terraform -chdir="\$FOUNDATION_DIR"' \
  "entrypoint does not isolate Terraform calls with -chdir"
require_text "scripts/aws-dev-foundation.sh" -- '-input=false' \
  "plan does not disable interactive input"
require_text "scripts/aws-dev-foundation.sh" -- '-lock-timeout=5m' \
  "plan does not use the required bounded lock timeout"
require_text "aws/environments/dev/foundation/dev.tfvars" 'cluster_public_access_cidrs[[:space:]]*=[[:space:]]*\["0\.0\.0\.0/0"\]' \
  "committed dev configuration does not preserve the approved global API CIDR"
require_text "aws/environments/dev/foundation/dev.tfvars" 'bootstrap_node_instance_types[[:space:]]*=[[:space:]]*\["m7i-flex\.large"\]' \
  "committed dev configuration does not use the account-compatible 2-vCPU/8-GiB bootstrap type"
require_text "aws/modules/environment-foundation/eks.tf" 'kms_key_administrators[[:space:]]*=[[:space:]]*sort\(tolist\(var\.bootstrap_admin_principal_arns\)\)' \
  "EKS secrets-key administrators must be pinned to the approved roles instead of the current caller"
require_text "aws/modules/environment-foundation/eks.tf" 'use_name_prefix[[:space:]]*=[[:space:]]*true' \
  "bootstrap node groups must use unique physical names for create-before-destroy replacement"
require_text "aws/modules/environment-foundation/eks.tf" 'enableNetworkPolicy[[:space:]]*=[[:space:]]*"true"' \
  "the Terraform-owned VPC CNI add-on must enable network-policy enforcement"

reject_text "scripts/aws-dev-foundation.sh" '(^|[[:space:]])(apply|destroy|kubectl)([[:space:]]|$)' \
  "entrypoint exposes a forbidden mutation command"
reject_text "aws/modules/environment-foundation" 'azurerm|azure|aks-dr|environment[[:space:]]*=[[:space:]]*"(staging|prod|production)"' \
  "AWS module contains Azure or future-environment scope"
reject_text "aws/environments/dev/foundation" 'azurerm|azure|aks-dr|module[[:space:]]+"state_backend"' \
  "dev foundation root couples to Azure, DR, or the US2 backend module"

printf 'PASS: AWS dev foundation shell contract\n'
