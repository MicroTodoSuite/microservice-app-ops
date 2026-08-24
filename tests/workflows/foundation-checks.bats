#!/usr/bin/env bash
# Root and workflow contract for the full-platform rollout (spec 009, T013).
#
# These checks read committed configuration only. They make no cloud call, so
# they can gate a pull request before any credential exists.
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKSPACE_ROOT="$(dirname "$OPS_ROOT")"
TOOLCHAIN_LOCK="${FULL_PROFILE_TOOLCHAIN_LOCK:-$WORKSPACE_ROOT/microservice-app-gitops/scripts/managed/full-profile-toolchain.lock}"

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

for dependency in jq find grep sort awk; do
  command -v "$dependency" >/dev/null 2>&1 || {
    printf 'FAIL: required command is missing: %s\n' "$dependency" >&2
    exit 1
  }
done

# The value of a `key = "..."` style HCL assignment, or empty when absent.
hcl_value() {
  local file="$1" name="$2"
  awk -v name="$name" '
    $1 == name && $2 == "=" {
      value = $3
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

mapfile -t backend_files < <(find "$OPS_ROOT/aws/environments" -name '*.tfbackend' | sort)
mapfile -t foundation_tfvars < <(find "$OPS_ROOT/aws/environments" -path '*/foundation/*.tfvars' | sort)
mapfile -t workflow_files < <(find "$OPS_ROOT/.github/workflows" -name '*.yml' | sort)

[[ "${#backend_files[@]}" -gt 0 ]] || fail "no Terraform backend configuration was found"
[[ "${#foundation_tfvars[@]}" -gt 0 ]] || fail "no foundation tfvars was found"

# --- State isolation -------------------------------------------------------
# Two roots sharing a state key silently overwrite each other's infrastructure.
declare -A seen_backend_key=()
for backend in "${backend_files[@]}"; do
  key="$(hcl_value "$backend" key)"
  [[ -n "$key" ]] || { fail "$backend declares no state key"; continue; }
  if [[ -n "${seen_backend_key[$key]:-}" ]]; then
    fail "state key '$key' is claimed by both ${seen_backend_key[$key]} and $backend"
  fi
  seen_backend_key["$key"]="$backend"

  [[ "$(hcl_value "$backend" encrypt)" == "true" ]] || fail "$backend does not require state encryption"
  [[ "$(hcl_value "$backend" use_lockfile)" == "true" ]] || fail "$backend does not require state locking"
done

# --- Environment identity and address space --------------------------------
declare -A seen_vpc_cidr=()
shared_resource_owners=0
for tfvars in "${foundation_tfvars[@]}"; do
  environment="$(hcl_value "$tfvars" environment)"
  [[ -n "$environment" ]] || fail "$tfvars declares no environment"

  account="$(hcl_value "$tfvars" expected_account_id)"
  [[ "$account" =~ ^[0-9]{12}$ ]] || fail "$tfvars declares no explicit 12-digit expected_account_id"

  region="$(hcl_value "$tfvars" aws_region)"
  [[ -n "$region" ]] || fail "$tfvars declares no explicit aws_region"

  cidr="$(hcl_value "$tfvars" vpc_cidr)"
  [[ -n "$cidr" ]] || fail "$tfvars declares no vpc_cidr"
  if [[ -n "${seen_vpc_cidr[$cidr]:-}" ]]; then
    fail "vpc_cidr $cidr is claimed by both ${seen_vpc_cidr[$cidr]} and $tfvars"
  fi
  seen_vpc_cidr["$cidr"]="$tfvars"

  if [[ "$(hcl_value "$tfvars" create_shared_resources)" == "true" ]]; then
    shared_resource_owners=$((shared_resource_owners + 1))
  fi

  # A public EKS API is a dev-only accepted tradeoff, documented in dev.tfvars.
  # No other environment may copy it.
  if [[ "$environment" != "dev" ]] && grep -q '0\.0\.0\.0/0' "$tfvars"; then
    fail "$tfvars exposes the EKS API to 0.0.0.0/0; only dev carries that reviewed exception"
  fi

  # The canonical domain and its traffic are separate named approvals. Neither
  # may arrive as a quiet tfvars edit.
  if grep -Eq '^[[:space:]]*create_canonical_hosted_zone[[:space:]]*=[[:space:]]*true' "$tfvars"; then
    fail "$tfvars enables the canonical hosted zone; that requires its own reviewed change"
  fi
  if grep -Eq '^[[:space:]]*canonical_destination_records[[:space:]]*=[[:space:]]*\{[[:space:]]*[^}]' "$tfvars"; then
    fail "$tfvars publishes a canonical destination record; enabling traffic requires a named traffic owner"
  fi
  if grep -Eq '^[[:space:]]*public_hosted_zone_name[[:space:]]*=[[:space:]]*"microtodosuite\.online"' "$tfvars"; then
    fail "$tfvars renames a legacy zone to the canonical domain, which would destroy it and its registrar delegation"
  fi
done

# Exactly one foundation owns the account-level singletons.
[[ "$shared_resource_owners" -eq 1 ]] ||
  fail "exactly one foundation must set create_shared_resources = true, found $shared_resource_owners"

# --- Workflow safety -------------------------------------------------------
if [[ -f "$TOOLCHAIN_LOCK" ]]; then
  pinned_terraform="$(jq -er '.tools[] | select(.name == "terraform") | .version' "$TOOLCHAIN_LOCK")" ||
    fail "the toolchain lock does not pin a Terraform version"
else
  fail "toolchain lock is missing: $TOOLCHAIN_LOCK"
  pinned_terraform=""
fi

# Scope: the AWS foundation workflows this specification governs. The legacy
# Azure Container Apps workflows are reported below but not gated here; their
# stale paths and pinning are a separate migration task and this contract must
# not be the thing that blocks unrelated work on them.
legacy_terraform_workflows=()

for workflow in "${workflow_files[@]}"; do
  grep -q 'terraform' "$workflow" || continue

  if ! grep -q 'aws/environments\|aws/modules' "$workflow"; then
    legacy_terraform_workflows+=("$(basename "$workflow")")
    continue
  fi

  # Terraform version pinning.
  if grep -q 'terraform_version:' "$workflow"; then
    while read -r version; do
      [[ "$version" == "$pinned_terraform" ]] ||
        fail "$workflow requests Terraform $version but the toolchain lock pins $pinned_terraform"
    done < <(awk -F': *' '/terraform_version:/ {gsub(/[" ]/, "", $2); print $2}' "$workflow")
  fi

  # No unattended apply. An apply must consume a plan a human approved.
  if grep -Eq 'terraform.*(apply|destroy)[^|]*-auto-approve' "$workflow"; then
    fail "$workflow applies or destroys without consuming an approved saved plan"
  fi

  # No long-lived credentials. Foundation workflows authenticate through OIDC.
  if grep -Eq 'aws-access-key-id|AWS_SECRET_ACCESS_KEY' "$workflow"; then
    fail "$workflow uses long-lived AWS credentials instead of OIDC role assumption"
  fi

  # A workflow that plans against a real backend must leave reviewable
  # artifacts: a saved plan, a cost delta, and an OIDC identity.
  if grep -Eq 'terraform[^#]*plan' "$workflow" && grep -q 'backend-config' "$workflow"; then
    grep -Eq 'plan[^#]*-out' "$workflow" ||
      fail "$workflow plans against a real backend without saving the plan it reviewed"
    grep -q 'infracost' "$workflow" ||
      fail "$workflow plans against a real backend without producing an Infracost delta"
    grep -q 'id-token: *write' "$workflow" ||
      fail "$workflow plans against a real backend without requesting an OIDC token"
  fi
done

if [[ "${#legacy_terraform_workflows[@]}" -gt 0 ]]; then
  printf 'NOTE: %d legacy Azure Terraform workflow(s) are outside this contract and still need migration: %s\n' \
    "${#legacy_terraform_workflows[@]}" "${legacy_terraform_workflows[*]}" >&2
fi

if [[ "$failures" -ne 0 ]]; then
  printf 'FAIL: %d foundation contract violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: state keys, environment identity, address space, DNS approvals and workflow safety hold.\n'
