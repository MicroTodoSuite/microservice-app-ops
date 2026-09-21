#!/usr/bin/env bash
# Source contract for the Azure disaster-recovery foundation (gitops
# specs/009-full-platform-rollout T118 and T119). It checks what terraform test
# cannot observe in a plan: the backend block and its example configuration,
# the absence of any Terraform-managed Key Vault secret or access policy, the
# absence of static credentials and credential-bearing outputs, and the pinned
# provider. It reads files only; it never contacts Azure.
#
#   tests/contract/azure-dr-foundation.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODULE_DIR="$ROOT/azure/modules/aks-foundation"
ROOT_DIR="$ROOT/azure/environments/dr/foundation"
BACKEND_EXAMPLE="$ROOT_DIR/foundation.azurerm.tfbackend.example"
AZURERM_VERSION="5.0.1"

failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

# Terraform sources of a directory, without tests or the .terraform cache.
tf_files() {
  find "$1" -maxdepth 1 -type f -name '*.tf' 2>/dev/null | sort
}

# Terraform sources with comments stripped, so a comment that names a
# forbidden construct to explain its absence is not mistaken for it.
tf_code() {
  local file
  while IFS= read -r file; do
    sed -E -e 's/[[:space:]]*(#|\/\/).*$//' "$file"
  done < <(tf_files "$1")
}

for directory in "$MODULE_DIR" "$ROOT_DIR"; do
  relative="${directory#"$ROOT"/}"
  if [[ -z "$(tf_files "$directory")" ]]; then
    fail "$relative has no Terraform sources"
    continue
  fi
  pass "$relative has Terraform sources"

  if tf_code "$directory" | grep -Eq '(resource|data|ephemeral)[[:space:]]+"azurerm_key_vault_secret"'; then
    fail "$relative declares an azurerm_key_vault_secret; the vault stays empty and only the seed workflow writes values"
  else
    pass "$relative declares no azurerm_key_vault_secret"
  fi

  if tf_code "$directory" | grep -Eq 'resource[[:space:]]+"azurerm_key_vault_access_policy"|^[[:space:]]*access_policy[[:space:]]*\{'; then
    fail "$relative grants Key Vault access through an access policy; the vault authorizes with Azure RBAC only"
  else
    pass "$relative grants no Key Vault access policy"
  fi

  forbidden='(^|[^a-z_])(client_secret|client_secret_file_path|client_certificate|client_certificate_password|client_certificate_path|access_key|sas_token|primary_access_key|secondary_access_key|admin_password|kube_config|kube_config_raw|kube_admin_config|kube_admin_config_raw|primary_connection_string|secondary_connection_string)([^a-z_]|$)'
  if tf_code "$directory" | grep -Eq "$forbidden"; then
    fail "$relative references a static credential or credential-bearing attribute: $(tf_code "$directory" | grep -Eo "$forbidden" | sort -u | tr -d ' \n')"
  else
    pass "$relative references no static credential or credential-bearing attribute"
  fi

  if tf_code "$directory" | grep -Eq '^[[:space:]]*sensitive[[:space:]]*=[[:space:]]*true'; then
    fail "$relative declares a sensitive value; this foundation outputs non-secret identifiers only"
  else
    pass "$relative declares no sensitive value"
  fi

  if tf_code "$directory" | grep -Eq 'admin_enabled[[:space:]]*=[[:space:]]*true'; then
    fail "$relative enables the registry admin user"
  else
    pass "$relative leaves the registry admin user disabled"
  fi

  if tf_code "$directory" | grep -Eq "source[[:space:]]*=[[:space:]]*\"hashicorp/azurerm\"" \
    && tf_code "$directory" | grep -Eq "version[[:space:]]*=[[:space:]]*\"=?[[:space:]]*${AZURERM_VERSION//./\\.}\""; then
    pass "$relative pins hashicorp/azurerm $AZURERM_VERSION"
  else
    fail "$relative must pin hashicorp/azurerm exactly $AZURERM_VERSION (spec 009 research decision 9)"
  fi
done

if [[ -n "$(tf_files "$MODULE_DIR")" ]]; then
  if tf_code "$MODULE_DIR" | grep -Eq 'backend[[:space:]]+"'; then
    fail "the module declares a backend; only the root owns state"
  fi
  if tf_code "$MODULE_DIR" | grep -Eq '^[[:space:]]*provider[[:space:]]+"azurerm"'; then
    fail "the module configures a provider; it must declare azurerm.project and receive it from the root (MTS-IAC-104)"
  fi
  if tf_code "$MODULE_DIR" | grep -Eq 'configuration_aliases[[:space:]]*=[[:space:]]*\[[^]]*azurerm\.project'; then
    pass "the module declares the azurerm.project configuration alias"
  else
    fail "the module must declare configuration_aliases = [azurerm.project] (MTS-IAC-104)"
  fi
fi

if [[ -n "$(tf_files "$ROOT_DIR")" ]]; then
  backend_count="$(tf_code "$ROOT_DIR" | grep -Ec 'backend[[:space:]]+"' || true)"
  azurerm_backend_count="$(tf_code "$ROOT_DIR" | grep -Ec 'backend[[:space:]]+"azurerm"' || true)"
  if [[ "$backend_count" == "1" && "$azurerm_backend_count" == "1" ]]; then
    pass "the root declares exactly one backend, azurerm, locked by Azure Blob leases"
  else
    fail "the root must declare exactly one backend and it must be azurerm (found $backend_count backends, $azurerm_backend_count azurerm)"
  fi

  if tf_code "$ROOT_DIR" | grep -Eq '^[[:space:]]*provider[[:space:]]+"azurerm"' \
    && tf_code "$ROOT_DIR" | grep -Eq 'alias[[:space:]]*=[[:space:]]*"principal"'; then
    pass "the root configures azurerm with alias principal"
  else
    fail "the root must configure provider \"azurerm\" with alias = \"principal\" (MTS-IAC-104)"
  fi

  if tf_code "$ROOT_DIR" | grep -Eq 'use_oidc[[:space:]]*=[[:space:]]*false|use_msi[[:space:]]*=[[:space:]]*true'; then
    fail "the root must not turn OIDC off or authenticate through a managed identity of its own"
  fi

  if tf_code "$ROOT_DIR" | grep -Eq 'azurerm\.project[[:space:]]*=[[:space:]]*azurerm\.principal'; then
    pass "the root passes azurerm.principal to the module as azurerm.project"
  else
    fail "the root must pass azurerm.principal to the module as azurerm.project"
  fi
fi

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

if [[ ! -f "$BACKEND_EXAMPLE" ]]; then
  fail "${BACKEND_EXAMPLE#"$ROOT"/} is missing; the preflight (T124) and every plan read the backend from it"
else
  state_key="$(backend_value key "$BACKEND_EXAMPLE")"
  for required in resource_group_name storage_account_name container_name key; do
    [[ -n "$(backend_value "$required" "$BACKEND_EXAMPLE")" ]] \
      || fail "the backend example must set $required"
  done
  [[ "$state_key" == *.tfstate ]] || fail "the backend state key must end in .tfstate"
  [[ "$(backend_value use_azuread_auth "$BACKEND_EXAMPLE")" == "true" ]] \
    || fail "the backend must authenticate with Microsoft Entra ID (use_azuread_auth = true)"
  if grep -Eq '^[[:space:]]*(access_key|sas_token|client_secret|client_certificate_password|msi_endpoint)[[:space:]]*=' "$BACKEND_EXAMPLE"; then
    fail "the backend example carries a static credential"
  fi

  # FR-009: no two roots may share a state key.
  collisions=0
  while IFS= read -r other; do
    [[ "$other" == "$BACKEND_EXAMPLE" ]] && continue
    other_key="$(backend_value key "$other")"
    if [[ -n "$state_key" && "$other_key" == "$state_key" ]]; then
      fail "state key $state_key is also used by ${other#"$ROOT"/}"
      collisions=$((collisions + 1))
    fi
  done < <(find "$ROOT/aws" "$ROOT/azure" -type f \( -name '*.tfbackend.example' -o -name '*.tfbackend' \) 2>/dev/null | sort)
  if [[ -n "$state_key" && "$collisions" -eq 0 ]]; then
    pass "state key $state_key is used by no other root"
  fi
fi

if [[ "$failures" -gt 0 ]]; then
  printf 'FAIL: %d Azure DR foundation contract violation(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: the Azure DR foundation source contract holds\n'
