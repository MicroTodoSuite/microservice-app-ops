#!/usr/bin/env bash
# Source contract for the economical profile's off-provider Azure backup roots.
# It reads tracked files only; it never initializes a backend or contacts Azure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKLOAD_ROOT="$ROOT/azure/environments/eco/workload"
SECURITY_ROOT="$ROOT/azure/environments/eco/security"
WORKLOAD_BACKEND="$WORKLOAD_ROOT/workload.azurerm.tfbackend.example"
SECURITY_BACKEND="$SECURITY_ROOT/security.azurerm.tfbackend.example"
AZURERM_VERSION="5.6.0"

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

tf_files() {
  find "$1" -maxdepth 1 -type f -name '*.tf' 2>/dev/null | sort
}

tf_code() {
  local file
  while IFS= read -r file; do
    sed -E -e 's/[[:space:]]*(#|\/\/).*$//' "$file"
  done < <(tf_files "$1")
}

require_code() {
  local code=$1 pattern=$2 message=$3
  if grep -Eq "$pattern" <<<"$code"; then
    pass "$message"
  else
    fail "$message"
  fi
}

reject_code() {
  local code=$1 pattern=$2 message=$3
  if grep -Eq "$pattern" <<<"$code"; then
    fail "$message"
  else
    pass "$message"
  fi
}

backend_value() {
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

for directory in "$WORKLOAD_ROOT" "$SECURITY_ROOT"; do
  relative="${directory#"$ROOT"/}"
  if [[ -z "$(tf_files "$directory")" ]]; then
    fail "$relative has no Terraform implementation"
    continue
  fi

  code="$(tf_code "$directory")"
  require_code "$code" 'source[[:space:]]*=[[:space:]]*"hashicorp/azurerm"' "$relative declares the AzureRM provider"
  require_code "$code" "version[[:space:]]*=[[:space:]]*\"=?[[:space:]]*${AZURERM_VERSION//./\\.}\"" "$relative pins AzureRM exactly to $AZURERM_VERSION"
  require_code "$code" 'provider[[:space:]]+"azurerm"' "$relative configures the AzureRM provider"
  require_code "$code" 'alias[[:space:]]*=[[:space:]]*"principal"' "$relative uses the azurerm.principal alias"
  require_code "$code" 'use_oidc[[:space:]]*=[[:space:]]*true' "$relative enables OIDC authentication"
  require_code "$code" 'storage_use_azuread[[:space:]]*=[[:space:]]*true' "$relative uses Microsoft Entra ID for the storage data plane"
  require_code "$code" 'backend[[:space:]]+"azurerm"' "$relative declares an AzureRM backend"

  reject_code "$code" 'source[[:space:]]*=[[:space:]]*"(\.\.?/|/)' "$relative consumes no local Terraform module"
  reject_code "$code" '(^|[^a-z_])(client_secret|client_certificate|access_key|sas_token|connection_string|primary_access_key|secondary_access_key)([^a-z_]|$)' "$relative contains no static credential or credential-bearing reference"
done

workload_code="$(tf_code "$WORKLOAD_ROOT")"
security_code="$(tf_code "$SECURITY_ROOT")"

for module_name in resource-group storage-account; do
  require_code "$workload_code" "git::https://github\\.com/MicroTodoSuite/terraform-azure-modules\\.git//${module_name}\\?ref=${module_name}-v[0-9]+\\.[0-9]+\\.[0-9]+" "the workload root pins the released $module_name module by exact tag"
done

for module_name in managed-identity role-assignment; do
  require_code "$security_code" "git::https://github\\.com/MicroTodoSuite/terraform-azure-modules\\.git//${module_name}\\?ref=${module_name}-v[0-9]+\\.[0-9]+\\.[0-9]+" "the security root pins the released $module_name module by exact tag"
done

require_code "$workload_code" 'backup_storage_contract_data' "the workload root exposes the non-secret backup storage contract"
require_code "$security_code" 'backup_identity_contract_data' "the security root exposes the non-secret backup identity contract"
require_code "$security_code" 'data[[:space:]]+"azurerm_storage_account"' "the security root reads the existing storage account"
require_code "$security_code" 'data[[:space:]]+"azurerm_storage_container"' "the security root reads the existing storage containers"
reject_code "$security_code" 'resource[[:space:]]+"azurerm_(resource_group|storage_account|storage_container)"' "the security root creates no workload storage resource"

for backend in "$WORKLOAD_BACKEND" "$SECURITY_BACKEND"; do
  relative="${backend#"$ROOT"/}"
  if [[ ! -f "$backend" ]]; then
    fail "$relative is missing"
    continue
  fi

  if [[ "$(backend_value use_azuread_auth "$backend")" == "true" ]]; then
    pass "$relative enables Entra authentication"
  else
    fail "$relative must set use_azuread_auth = true"
  fi
  if [[ "$(backend_value use_oidc "$backend")" == "true" ]]; then
    pass "$relative enables OIDC authentication"
  else
    fail "$relative must set use_oidc = true"
  fi
  if [[ "$(backend_value key "$backend")" == *.tfstate ]]; then
    pass "$relative has a Terraform state key"
  else
    fail "$relative must set a .tfstate key"
  fi
  if grep -Eq '^[[:space:]]*(access_key|sas_token|client_secret|client_certificate_password)[[:space:]]*=' "$backend"; then
    fail "$relative carries a static credential"
  fi
done

if [[ -f "$WORKLOAD_BACKEND" && -f "$SECURITY_BACKEND" ]]; then
  workload_key="$(backend_value key "$WORKLOAD_BACKEND")"
  security_key="$(backend_value key "$SECURITY_BACKEND")"
  if [[ -n "$workload_key" && -n "$security_key" && "$workload_key" != "$security_key" ]]; then
    pass "the workload and security roots use distinct state keys"
  else
    fail "the workload and security roots must use distinct non-empty state keys"
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  printf 'FAIL: %d economical Azure backup contract violation(s)\n' "$failures" >&2
  exit 1
fi

printf 'PASS: the economical Azure backup source contract holds\n'
