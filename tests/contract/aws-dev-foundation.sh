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
require_file "aws/modules/environment-foundation/managed-secrets.tf"
require_file "aws/modules/environment-jwt-values/main.tf"
require_file "aws/modules/environment-foundation/github-oidc.tf"
require_file "aws/modules/environment-foundation/kyverno-irsa.tf"
require_file "aws/modules/environment-foundation/route53.tf"
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
require_text "aws/environments/dev/foundation/dev.tfvars" 'bootstrap_node_ami_release_version[[:space:]]*=[[:space:]]*"1\.35\.6-20260818"' \
  "committed dev configuration does not pin the currently running node AMI release"
require_text "aws/modules/environment-foundation/eks.tf" 'kms_key_administrators[[:space:]]*=[[:space:]]*sort\(tolist\(var\.bootstrap_admin_principal_arns\)\)' \
  "EKS secrets-key administrators must be pinned to the approved roles instead of the current caller"
require_text "aws/modules/environment-foundation/eks.tf" 'use_name_prefix[[:space:]]*=[[:space:]]*true' \
  "bootstrap node groups must use unique physical names for create-before-destroy replacement"
require_text "aws/modules/environment-foundation/eks.tf" 'ami_release_version[[:space:]]*=[[:space:]]*var\.bootstrap_node_ami_release_version' \
  "bootstrap node AMI release is not wired to the reviewed pin"
require_text "aws/modules/environment-foundation/eks.tf" 'use_latest_ami_release_version[[:space:]]*=[[:space:]]*false' \
  "bootstrap node groups must not roll during an unrelated foundation apply"
require_text "aws/modules/environment-foundation/eks.tf" 'enableNetworkPolicy[[:space:]]*=[[:space:]]*"true"' \
  "the Terraform-owned VPC CNI add-on must enable network-policy enforcement"
require_text "aws/modules/environment-foundation/ecr.tf" 'resource "aws_ecr_repository" "neutral_services"' \
  "neutral ECR repositories are not declared additively"
require_text "aws/modules/environment-foundation/ecr.tf" 'name[[:space:]]*=[[:space:]]*"\$\{var\.project\}/\$\{each\.key\}"' \
  "neutral repositories do not use the exact project/service path"
require_file "aws/environments/dev/foundation/release-secrets.tf"
require_text "aws/modules/environment-jwt-values/main.tf" 'ephemeral "random_password" "environment_jwt"' \
  "JWT values are not generated through the local ephemeral resource"
require_text "aws/environments/dev/foundation/release-secrets.tf" 'module "environment_jwt_values"' \
  "foundation root does not compose the independently testable ephemeral boundary"
require_text "aws/modules/environment-foundation/managed-secrets.tf" 'secret_string_wo[[:space:]]*=' \
  "JWT values are not supplied through a write-only argument"
require_text "aws/modules/environment-foundation/managed-secrets.tf" 'resource "aws_secretsmanager_secret_version" "environment_jwt"' \
  "three write-only JWT secret versions are not declared"
require_text "aws/modules/environment-foundation/managed-secrets.tf" 'secret_string_wo_version[[:space:]]*=[[:space:]]*var\.environment_jwt_secret_version' \
  "JWT write-only version changes are not controlled by the rotation input"
require_text "aws/modules/environment-foundation/managed-secrets.tf" 'system:serviceaccount:microtodo-\$\{environment\}:external-secrets-jwt' \
  "JWT reader trust does not derive the exact environment ServiceAccount subjects"
require_text "aws/modules/environment-foundation/github-oidc.tf" 'token\.actions\.githubusercontent\.com' \
  "GitHub Actions OIDC provider is missing"
require_text "aws/modules/environment-foundation/github-oidc.tf" 'microtodosuite-github-ecr-publisher' \
  "the exact GitHub ECR publisher role is missing"
require_text "aws/modules/environment-foundation/kyverno-irsa.tf" 'microtodosuite-kyverno-ecr-verifier' \
  "the exact Kyverno ECR verifier role is missing"
require_text "aws/modules/environment-foundation/variables.tf" 'repo:MicroTodoSuite/microservice-app-auth-api:ref:refs/heads/main' \
  "GitHub publisher subjects are not constrained to reviewed main"
require_text "aws/modules/environment-foundation/route53.tf" 'resource "aws_route53_zone" "public"' \
  "the Terraform-owned public Route 53 hosted zone is missing"
require_text "aws/modules/environment-foundation/route53.tf" 'force_destroy[[:space:]]*=[[:space:]]*false' \
  "the public hosted zone must not permit destructive record cleanup"
require_text "aws/environments/dev/foundation/dev.tfvars" 'public_hosted_zone_name[[:space:]]*=[[:space:]]*"microtodosuite\.abrdns\.com"' \
  "the committed foundation does not select the registered public domain"
require_text "aws/environments/dev/foundation/outputs.tf" 'output "public_hosted_zone_name_servers"' \
  "the dev foundation does not expose registrar delegation name servers"

reject_text "scripts/aws-dev-foundation.sh" '(^|[[:space:]])(apply|destroy|kubectl)([[:space:]]|$)' \
  "entrypoint exposes a forbidden mutation command"
reject_text "aws/modules/environment-foundation" 'azurerm|azure|aks-dr|environment[[:space:]]*=[[:space:]]*"(staging|prod|production)"' \
  "AWS module contains Azure or future-environment scope"
reject_text "aws/environments/dev/foundation" 'azurerm|azure|aks-dr|module[[:space:]]+"state_backend"' \
  "dev foundation root couples to Azure, DR, or the US2 backend module"
reject_text "aws" 'secret_string[[:space:]]*=' \
  "an ordinary state-persisted Secrets Manager value is forbidden"
reject_text "aws" 'resource[[:space:]]+"aws_acm_' \
  "ACM certificate creation must wait for verified registrar delegation"
# Constitution 3.0.0 authorized the full-profile rollout, which introduces the
# canonical microtodosuite.online zone and, later, one alias record pointing at
# it. The blanket ban on aws_route53_record that guarded the earlier
# hosted-zone-only scope is therefore replaced by the two properties that
# actually matter now: a record must be gated behind owning the canonical zone,
# and the destination input must default empty so enabling real traffic stays a
# separate named approval.
require_text "aws/modules/environment-foundation/route53.tf" \
  'for_each[[:space:]]*=[[:space:]]*var\.create_canonical_hosted_zone \? var\.canonical_destination_records : \{\}' \
  "canonical DNS records are not gated behind owning the canonical zone"
require_text "aws/modules/environment-foundation/variables.tf" \
  'variable "canonical_destination_records"' \
  "the canonical destination input is missing"
reject_text "aws/environments" 'canonical_destination_records[[:space:]]*=[[:space:]]*\{[[:space:]]*[^}[:space:]]' \
  "an environment publishes a canonical destination record without a named traffic-owner approval"
reject_text "aws" '(AKIA[0-9A-Z]{16}|AWS_SECRET_ACCESS_KEY[[:space:]]*=|JWT_SECRET[[:space:]]*=)' \
  "static AWS or JWT secret material is forbidden"

printf 'PASS: AWS dev foundation shell contract\n'
