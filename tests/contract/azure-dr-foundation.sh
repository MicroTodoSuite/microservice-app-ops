#!/usr/bin/env bash
# Source contract for the Azure disaster-recovery roots under
# azure/environments/fprd (gitops specs/009-full-platform-rollout US5). It
# checks what terraform test and the organization's rule contracts do not: the
# six expected domain roots and their backends, modules taken only from
# terraform-azure-modules by an exact tag of the same module, the absence of
# any Terraform-managed Key Vault secret or access policy, the absence of
# static credentials and credential-bearing outputs, OIDC left on, and state
# keys no other Azure root uses. It reads files only; it never contacts Azure.
#
#   tests/contract/azure-dr-foundation.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FPRD="$ROOT/azure/environments/fprd"
DOMAINS=(state networking registry security workload security-federation)
MODULE_SOURCE='^git::https://github\.com/MicroTodoSuite/terraform-azure-modules\.git//([a-z0-9-]+)\?ref=([a-z0-9-]+)-v[0-9]+\.[0-9]+\.[0-9]+$'

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
# string, such as a module source URL, is code. Callers
# capture it once and grep the capture: under pipefail, grep -q exiting on its
# first match would otherwise turn every positive match into a failure.
tf_code() {
  local file
  while IFS= read -r file; do
    sed -E -e 's/^[[:space:]]*(#|\/\/).*$//' -e 's/[[:space:]]+#[^"]*$//' "$file"
  done < <(tf_files "$1")
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

if [[ -d "$ROOT/azure/modules" ]]; then
  fail "azure/modules exists; Azure modules live in terraform-azure-modules and are consumed by tag (MTS-IAC-102)"
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

  forbidden='(^|[^a-z_])(client_secret|client_secret_file_path|client_certificate|client_certificate_password|client_certificate_path|access_key|sas_token|primary_access_key|secondary_access_key|admin_password|kube_config|kube_config_raw|kube_admin_config|kube_admin_config_raw|primary_connection_string|secondary_connection_string)([^a-z_]|$)'
  if grep -Eq "$forbidden" <<<"$code"; then
    fail "$relative references a static credential or credential-bearing attribute: $(grep -Eo "$forbidden" <<<"$code" | sort -u | tr -d ' \n')"
  fi

  if grep -Eq '^[[:space:]]*sensitive[[:space:]]*=[[:space:]]*true' <<<"$code"; then
    fail "$relative declares a sensitive value; these roots output non-secret identifiers only"
  fi

  if grep -Eq 'use_oidc[[:space:]]*=[[:space:]]*false|use_msi[[:space:]]*=[[:space:]]*true' <<<"$code"; then
    fail "$relative turns OIDC off or authenticates through a managed identity of its own"
  fi

  # Every module comes from terraform-azure-modules at an exact tag of that
  # same module (MTS-IAC-102, PC-IAC-015).
  while IFS= read -r source; do
    [[ -z "$source" ]] && continue
    if [[ "$source" =~ $MODULE_SOURCE ]] && [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" ]]; then
      continue
    fi
    fail "$relative sources a module outside terraform-azure-modules or without its own exact tag: $source"
  done < <(sed -nE 's/^[[:space:]]*source[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' <<<"$code" | grep -v '^hashicorp/' || true)

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
  key="$(backend_value key "$example")"
  [[ "$key" == "fprd/$domain/terraform.tfstate" ]] \
    || fail "${example#"$ROOT"/} must use the key fprd/$domain/terraform.tfstate, not '$key'"
  [[ "$(backend_value use_azuread_auth "$example")" == "true" ]] \
    || fail "${example#"$ROOT"/} must authenticate with Microsoft Entra ID (use_azuread_auth = true)"
  if grep -Eq '^[[:space:]]*(access_key|sas_token|client_secret|client_certificate_password|msi_endpoint)[[:space:]]*=' "$example"; then
    fail "${example#"$ROOT"/} carries a static credential"
  fi
  # FR-009: no two roots of the same backend may share a state key.
  if [[ -n "$key" && -n "${state_keys[$key]:-}" ]]; then
    fail "state key $key is used by both ${state_keys[$key]} and $relative"
  fi
  state_keys[$key]="$relative"
done

if [[ "$failures" -gt 0 ]]; then
  printf 'FAIL: %d Azure DR source contract violation(s)\n' "$failures" >&2
  exit 1
fi
printf 'PASS: the Azure DR source contract holds for %d roots\n' "${#DOMAINS[@]}"
