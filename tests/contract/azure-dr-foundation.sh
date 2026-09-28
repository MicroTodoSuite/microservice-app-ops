#!/usr/bin/env bash
# Source contract for the Azure disaster-recovery roots under
# azure/environments/fprd (gitops specs/009-full-platform-rollout US5, T119 and
# T126). It checks what terraform test and the organization's rule contracts do
# not: the six domain roots and their backends, modules taken only from
# terraform-azure-modules by an exact tag of the same module, the exact AzureRM
# pin, the absence of any Terraform-managed Key Vault secret or access policy,
# of static credentials and of credential-bearing outputs, OIDC left on, state
# keys no other Azure root uses, the collision-free VNet selection, a node pool
# that fits the subscription's quota, no committed real backend or variable
# file, and a plan-only workflow. It reads files only; it never contacts Azure.
#
#   tests/contract/azure-dr-foundation.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FPRD="$ROOT/azure/environments/fprd"
WORKFLOW="$ROOT/.github/workflows/azure-dr-foundation-checks.yml"
DOMAINS=(state networking registry security workload security-federation)
MODULE_SOURCE='^git::https://github\.com/MicroTodoSuite/terraform-azure-modules\.git//([a-z0-9-]+)\?ref=([a-z0-9-]+)-v[0-9]+\.[0-9]+\.[0-9]+$'
# The release the terraform-azure-modules samples are tested with (T125).
AZURERM_VERSION="5.0.1"
# Azure for Students ceiling, confirmed read-only on 2026-09-21 (gitops
# specs/009 T133 scope reconciliation): six regional vCPUs, four of them in
# the DSv4 family, none in DSv5.
REGIONAL_VCPUS=6
DSV4_VCPUS=4

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

# Terraform sources of one root, without tests or the .terraform cache.
tf_files() {
  find "$1" -maxdepth 1 -type f -name '*.tf' 2>/dev/null | sort
}

# Terraform sources with comments stripped, so a comment that names a
# forbidden construct to explain its absence is not mistaken for it. Only
# whole-line comments and trailing # comments are removed: a // inside a
# string, such as a module source URL, is code. Callers capture it once and
# grep the capture: under pipefail, grep -q exiting on its first match would
# otherwise turn every positive match into a failure.
tf_code() {
  local file
  while IFS= read -r file; do
    sed -E -e 's/^[[:space:]]*(#|\/\/).*$//' -e 's/[[:space:]]+#[^"]*$//' "$file"
  done < <(tf_files "$1")
}

# The value of a `name = value` assignment in an HCL file, unquoted, or empty.
hcl_value() {
  awk -v wanted="$1" '
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
    }
    line ~ "^[[:space:]]*" wanted "[[:space:]]*=" {
      sub(/^[^=]*=[[:space:]]*/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/^"|"$/, "", line)
      print line
      exit
    }
  ' "$2"
}

if [[ -d "$ROOT/azure/modules" ]]; then
  fail "azure/modules exists; Azure modules live in terraform-azure-modules and are consumed by tag (MTS-IAC-102)"
fi
if [[ -d "$ROOT/azure/environments/dr" ]]; then
  fail "azure/environments/dr exists; the DR estate is split by domain under azure/environments/fprd (PC-IAC-022)"
fi

declare -A state_keys=()

for domain in "${DOMAINS[@]}"; do
  directory="$FPRD/$domain"
  relative="${directory#"$ROOT"/}"
  if [[ -z "$(tf_files "$directory")" ]]; then
    fail "$relative has no Terraform sources"
    continue
  fi
  code="$(tf_code "$directory")"

  if grep -Eq '(resource|data|ephemeral)[[:space:]]+"azurerm_key_vault_secret"' <<<"$code"; then
    fail "$relative declares an azurerm_key_vault_secret; the vault stays empty and only the seed workflow writes values"
  fi

  if grep -Eq 'resource[[:space:]]+"azurerm_key_vault_access_policy"|^[[:space:]]*access_policy[[:space:]]*\{' <<<"$code"; then
    fail "$relative grants Key Vault access through an access policy; the vault authorizes with Azure RBAC only"
  fi

  forbidden='(^|[^a-z_])(client_secret|client_secret_file_path|client_certificate|client_certificate_password|client_certificate_path|access_key|sas_token|primary_access_key|secondary_access_key|admin_password|admin_username|kube_config|kube_config_raw|kube_admin_config|kube_admin_config_raw|primary_connection_string|secondary_connection_string)([^a-z_]|$)'
  if grep -Eq "$forbidden" <<<"$code"; then
    fail "$relative references a static credential or credential-bearing attribute: $(grep -Eo "$forbidden" <<<"$code" | sort -u | tr -d ' \n')"
  fi

  if grep -Eq '^[[:space:]]*sensitive[[:space:]]*=[[:space:]]*true' <<<"$code"; then
    fail "$relative declares a sensitive value; these roots output non-secret identifiers only"
  fi

  if grep -Eq 'use_oidc[[:space:]]*=[[:space:]]*false|use_msi[[:space:]]*=[[:space:]]*true' <<<"$code"; then
    fail "$relative turns OIDC off or authenticates through a managed identity of its own"
  fi

  # Exact provider pin in every root (PC-IAC-006).
  if grep -Eq "version[[:space:]]*=[[:space:]]*\"${AZURERM_VERSION//./\\.}\"" <<<"$code"; then
    pass "$relative pins azurerm $AZURERM_VERSION"
  else
    fail "$relative must pin azurerm exactly to $AZURERM_VERSION"
  fi
  [[ -f "$directory/.terraform.lock.hcl" ]] || fail "$relative does not commit its .terraform.lock.hcl"

  # Every module comes from terraform-azure-modules at an exact tag of that
  # same module (MTS-IAC-102, PC-IAC-015).
  module_count=0
  while IFS= read -r source; do
    [[ -z "$source" ]] && continue
    module_count=$((module_count + 1))
    if [[ "$source" =~ $MODULE_SOURCE ]] && [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
      continue
    fi
    fail "$relative sources a module outside terraform-azure-modules or without its own exact tag: $source"
  done < <(sed -nE 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' <<<"$code" | grep -v '^hashicorp/' || true)
  [[ "$module_count" -gt 0 ]] || fail "$relative calls no released module"

  backend_count="$(grep -Ec 'backend[[:space:]]+"' <<<"$code" || true)"
  if [[ "$domain" == "state" ]]; then
    if [[ "$backend_count" == "1" ]] && grep -Eq 'backend[[:space:]]+"local"' <<<"$code"; then
      pass "$relative bootstraps on local state"
    else
      fail "$relative must keep local state: it creates the account every other Azure root's state lives in"
    fi
    continue
  fi

  if [[ "$backend_count" == "1" ]] && grep -Eq 'backend[[:space:]]+"azurerm"[[:space:]]*\{[[:space:]]*\}' <<<"$code"; then
    pass "$relative declares one partial azurerm backend"
  else
    fail "$relative must declare exactly one partial azurerm backend"
  fi

  example="$directory/$domain.azurerm.tfbackend.example"
  if [[ ! -f "$example" ]]; then
    fail "${example#"$ROOT"/} is missing"
    continue
  fi
  key="$(hcl_value key "$example")"
  [[ "$key" == "fprd/$domain/terraform.tfstate" ]] \
    || fail "${example#"$ROOT"/} must use the key fprd/$domain/terraform.tfstate, not '$key'"
  [[ "$(hcl_value use_azuread_auth "$example")" == "true" ]] \
    || fail "${example#"$ROOT"/} must authenticate with Microsoft Entra ID (use_azuread_auth = true)"
  if grep -Eq '^[[:space:]]*(access_key|sas_token|client_secret|client_certificate_password|msi_endpoint)[[:space:]]*=' "$example"; then
    fail "${example#"$ROOT"/} carries a static credential"
  fi
  # FR-009: no two roots of the same backend may share a state key; each blob
  # is then locked by its own lease.
  if [[ -n "$key" && -n "${state_keys[$key]:-}" ]]; then
    fail "state key $key is used by both ${state_keys[$key]} and $relative"
  fi
  state_keys[$key]="$relative"
done

# Only templates are committed: a real backend or variable file carries the
# operator's subscription and must stay local (PC-IAC-024).
if committed="$(git -C "$ROOT" ls-files -- 'azure/environments/fprd' 2>/dev/null)"; then
  while IFS= read -r file; do
    case "$file" in
      *.tfbackend | *.tfvars | *.tfstate | *.tfstate.backup | *.tfplan)
        fail "$file is committed; only the .example templates belong in the repository" ;;
    esac
  done <<<"$committed"
fi

# Maintainer decision, 2026-09-21: the DR VNet moves from the rejected
# 10.50.0.0/16 candidate, which the AWS egress hub owns, to 10.60.0.0/16; the
# node subnet is its first /22. The reviewed example must carry the selection
# so an operator cannot bootstrap an obsolete placeholder.
network_example="$FPRD/networking/fprd.tfvars.example"
if [[ -f "$network_example" ]]; then
  for pair in "vnet_cidr=10.60.0.0/16" "node_subnet_cidr=10.60.0.0/22"; do
    name="${pair%%=*}"
    wanted="${pair#*=}"
    if [[ "$(hcl_value "$name" "$network_example")" == "$wanted" ]]; then
      pass "${network_example#"$ROOT"/} selects $name = $wanted"
    else
      fail "${network_example#"$ROOT"/} must select $name = $wanted"
    fi
  done
else
  fail "${network_example#"$ROOT"/} is missing"
fi

# MTS-IAC-104: the node pool fits the quota before anything is planned. The
# reviewed default is a DSv4 size whose autoscaler maximum stays within the
# family's four vCPUs, and so within the six regional ones.
workload_example="$FPRD/workload/fprd.tfvars.example"
if [[ -f "$workload_example" ]]; then
  vm_size="$(hcl_value vm_size "$workload_example")"
  vcpus="$(hcl_value vcpus "$workload_example")"
  max_count="$(hcl_value max_count "$workload_example")"
  quota="$(hcl_value regional_vcpu_quota "$workload_example")"
  if [[ "$vm_size" =~ ^Standard_D[0-9]+s_v4$ && "$vcpus" =~ ^[0-9]+$ && "$max_count" =~ ^[0-9]+$ && "$quota" =~ ^[0-9]+$ ]] \
    && ((vcpus * max_count <= quota && quota <= DSV4_VCPUS && quota <= REGIONAL_VCPUS)); then
    pass "${workload_example#"$ROOT"/} sizes $max_count x $vm_size ($((vcpus * max_count)) vCPUs) within the DSv4 quota of $DSV4_VCPUS"
  else
    fail "${workload_example#"$ROOT"/} must size a DSv4 pool whose maximum fits $DSV4_VCPUS DSv4 vCPUs (found vm_size='$vm_size' vcpus='$vcpus' max_count='$max_count' regional_vcpu_quota='$quota')"
  fi
else
  fail "${workload_example#"$ROOT"/} is missing"
fi

# The workflow plans only: Terraform 1.15.8, Azure OIDC, a saved plan, and
# Infracost, and never an apply, a destroy, or a client secret.
if [[ -f "$WORKFLOW" ]]; then
  workflow="${WORKFLOW#"$ROOT"/}"
  pinned="$(tr -d '[:space:]' <"$ROOT/.terraform-version")"
  mapfile -t versions < <(awk -F': *' '/terraform_version:/ {gsub(/[" '"'"']/, "", $2); print $2}' "$WORKFLOW")
  if [[ "${#versions[@]}" -gt 0 && "$pinned" == "1.15.8" ]] && ! printf '%s\n' "${versions[@]}" | grep -vqx "$pinned"; then
    pass "$workflow installs Terraform $pinned"
  else
    fail "$workflow must install exactly Terraform 1.15.8, the version .terraform-version pins"
  fi
  # Comment lines are prose, such as the explanation that nothing applies.
  workflow_code="$(grep -Ev '^[[:space:]]*#' "$WORKFLOW")"
  if grep -Eq '(terraform|-chdir=[^ ]*)[^#]*[[:space:]](apply|destroy)([[:space:]]|$)|-auto-approve' <<<"$workflow_code"; then
    fail "$workflow runs terraform apply or destroy; it must stay plan-only"
  fi
  grep -Eq "ARM_USE_OIDC:[[:space:]]*'?true'?" "$WORKFLOW" || fail "$workflow must authenticate to Azure through OIDC (ARM_USE_OIDC)"
  grep -Eq 'id-token:[[:space:]]*write' "$WORKFLOW" || fail "$workflow must request an OIDC token (id-token: write)"
  if grep -Eq 'ARM_CLIENT_SECRET|ARM_CLIENT_CERTIFICATE|ARM_ACCESS_KEY|ARM_SAS_TOKEN|creds:' "$WORKFLOW"; then
    fail "$workflow carries a static Azure credential"
  fi
  grep -Eq 'plan[^#]*-out=' "$WORKFLOW" || fail "$workflow must save the plan it summarizes"
  grep -q 'infracost breakdown' "$WORKFLOW" || fail "$workflow must produce an Infracost estimate"
  # The state root keeps local state and is planned by the operator only.
  matrix="$(grep -E '^[[:space:]]*domain:[[:space:]]*\[' <<<"$workflow_code" || true)"
  for domain in "${DOMAINS[@]}"; do
    [[ "$domain" == "state" ]] && continue
    grep -Eq "(\[|,)[[:space:]]*${domain}[[:space:]]*(,|\])" <<<"$matrix" || fail "$workflow does not plan the $domain root"
  done
else
  fail ".github/workflows/azure-dr-foundation-checks.yml is missing"
fi

if [[ "$failures" -gt 0 ]]; then
  printf 'FAIL: %d Azure DR source contract violation(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: the Azure DR source contract holds for %d roots and their workflow\n' "${#DOMAINS[@]}"
