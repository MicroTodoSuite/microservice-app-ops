#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_ROOT="$(dirname "$OPS_ROOT")"
TOOLCHAIN_LOCK="${FULL_PROFILE_TOOLCHAIN_LOCK:-$WORKSPACE_ROOT/microservice-app-gitops/scripts/managed/full-profile-toolchain.lock}"

CANDIDATE_VNET_CIDR=""
BACKEND_CONFIG=""
TERRAFORM_ROOT=""
OUTPUT=""

usage() {
  cat >&2 <<'EOF'
Usage: azure-dr.sh --candidate-vnet-cidr CIDR --backend-config FILE \
  --terraform-root DIR --output FILE
EOF
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --candidate-vnet-cidr)
      [[ "$#" -ge 2 ]] || fail "--candidate-vnet-cidr requires a value"
      CANDIDATE_VNET_CIDR="$2"
      shift 2
      ;;
    --backend-config)
      [[ "$#" -ge 2 ]] || fail "--backend-config requires a value"
      BACKEND_CONFIG="$2"
      shift 2
      ;;
    --terraform-root)
      [[ "$#" -ge 2 ]] || fail "--terraform-root requires a value"
      TERRAFORM_ROOT="$2"
      shift 2
      ;;
    --output)
      [[ "$#" -ge 2 ]] || fail "--output requires a value"
      OUTPUT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -n "$CANDIDATE_VNET_CIDR" ]] || fail "--candidate-vnet-cidr is required"
[[ -f "$BACKEND_CONFIG" ]] || fail "backend config is missing: $BACKEND_CONFIG"
[[ -d "$TERRAFORM_ROOT" ]] || fail "Terraform root is missing: $TERRAFORM_ROOT"
[[ -n "$OUTPUT" ]] || fail "--output is required"
[[ -n "${AZURE_SUBSCRIPTION_ID_COLONIA:-}" ]] \
  || fail "AZURE_SUBSCRIPTION_ID_COLONIA is required"
[[ -n "${AZURE_LOCATION:-}" ]] || fail "AZURE_LOCATION is required"
[[ -f "$TOOLCHAIN_LOCK" ]] || fail "toolchain lock is missing: $TOOLCHAIN_LOCK"

for dependency in jq python3 sha256sum grep; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required command is missing: $dependency"
done

AZ_BIN="$(command -v az || true)"
[[ -n "$AZ_BIN" ]] || fail "Azure CLI is not installed"

PINNED_AZURE_CLI_VERSION="$(jq -er '
  [.tools[] | select(.name == "azure-cli")] as $matches |
  if ($matches | length) == 1 then $matches[0].version else error("azure-cli lock entry must be unique") end
' "$TOOLCHAIN_LOCK")" || fail "cannot read the pinned Azure CLI version"
PINNED_AZURE_CLI_SHA256="$(jq -er '
  .tools[] | select(.name == "azure-cli") | .sha256 |
  select(test("^[a-f0-9]{64}$"))
' "$TOOLCHAIN_LOCK")" || fail "Azure CLI artifact checksum is missing or invalid"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$AZ_BIN" version --output json >"$TMP_DIR/version.json"
ACTUAL_AZURE_CLI_VERSION="$(jq -er '."azure-cli"' "$TMP_DIR/version.json")" \
  || fail "Azure CLI did not report a version"
[[ "$ACTUAL_AZURE_CLI_VERSION" == "$PINNED_AZURE_CLI_VERSION" ]] \
  || fail "Azure CLI version mismatch: expected $PINNED_AZURE_CLI_VERSION, got $ACTUAL_AZURE_CLI_VERSION"

"$AZ_BIN" account show --output json >"$TMP_DIR/account.json"
ACTUAL_SUBSCRIPTION="$(jq -er '.id' "$TMP_DIR/account.json")" \
  || fail "authenticated Azure subscription ID is unavailable"
[[ "$ACTUAL_SUBSCRIPTION" == "$AZURE_SUBSCRIPTION_ID_COLONIA" ]] \
  || fail "authenticated Azure subscription does not match AZURE_SUBSCRIPTION_ID_COLONIA"
[[ "$(jq -er '.state' "$TMP_DIR/account.json")" == "Enabled" ]] \
  || fail "authenticated Azure subscription is not enabled"
TENANT_ID="$(jq -er '.tenantId' "$TMP_DIR/account.json")" \
  || fail "authenticated Azure tenant ID is unavailable"
TENANT_ID_HASH="$(printf '%s' "$TENANT_ID" | sha256sum | awk '{print $1}')"

"$AZ_BIN" account list-locations --output json >"$TMP_DIR/locations.json"
jq -e --arg location "$AZURE_LOCATION" \
  'any(.[]; .name == $location)' "$TMP_DIR/locations.json" >/dev/null \
  || fail "AZURE_LOCATION is not available to the authenticated subscription"

"$AZ_BIN" network vnet list --output json >"$TMP_DIR/vnets.json"
python3 - "$CANDIDATE_VNET_CIDR" "$TMP_DIR/vnets.json" "$TMP_DIR/collisions.json" <<'PY'
import ipaddress
import json
import sys

try:
    candidate = ipaddress.ip_network(sys.argv[1], strict=True)
except ValueError as exc:
    raise SystemExit(f"FAIL: invalid candidate VNet CIDR: {exc}") from exc

with open(sys.argv[2], encoding="utf-8") as handle:
    vnets = json.load(handle)

collisions = []
for vnet in vnets:
    for prefix in vnet.get("addressSpace", {}).get("addressPrefixes", []):
        try:
            discovered = ipaddress.ip_network(prefix, strict=False)
        except ValueError as exc:
            raise SystemExit(f"FAIL: Azure returned an invalid VNet prefix {prefix}: {exc}") from exc
        if candidate.overlaps(discovered):
            collisions.append({
                "name": vnet.get("name", "unknown"),
                "resourceGroup": vnet.get("resourceGroup", "unknown"),
                "prefix": str(discovered),
            })

with open(sys.argv[3], "w", encoding="utf-8") as handle:
    json.dump(collisions, handle, sort_keys=True)
    handle.write("\n")
PY
[[ "$(jq 'length' "$TMP_DIR/collisions.json")" -eq 0 ]] \
  || fail "candidate VNet CIDR overlaps an existing Azure VNet"

"$AZ_BIN" provider list --output json >"$TMP_DIR/providers.json"
REQUIRED_PROVIDERS='["Microsoft.ContainerService","Microsoft.Network","Microsoft.ContainerRegistry","Microsoft.KeyVault","Microsoft.Storage"]'
jq -n \
  --argjson required "$REQUIRED_PROVIDERS" \
  --slurpfile providers "$TMP_DIR/providers.json" '
    $required - [
      $providers[0][] |
      select(.registrationState == "Registered") |
      .namespace
    ]
  ' >"$TMP_DIR/missing-providers.json"
[[ "$(jq 'length' "$TMP_DIR/missing-providers.json")" -eq 0 ]] \
  || fail "one or more required Azure providers are not registered"

backend_value() {
  local key="$1"
  awk -v wanted="$key" '
    $1 == wanted {
      sub(/^[^=]*=[[:space:]]*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/^"|"$/, "")
      print
      exit
    }
  ' "$BACKEND_CONFIG"
}

BACKEND_RESOURCE_GROUP="$(backend_value resource_group_name)"
BACKEND_STORAGE_ACCOUNT="$(backend_value storage_account_name)"
BACKEND_CONTAINER="$(backend_value container_name)"
BACKEND_KEY="$(backend_value key)"
BACKEND_AAD_AUTH="$(backend_value use_azuread_auth)"

[[ -n "$BACKEND_RESOURCE_GROUP" ]] || fail "backend resource_group_name is missing"
[[ -n "$BACKEND_STORAGE_ACCOUNT" ]] || fail "backend storage_account_name is missing"
[[ -n "$BACKEND_CONTAINER" ]] || fail "backend container_name is missing"
[[ -n "$BACKEND_KEY" ]] || fail "backend key is missing"
[[ "$BACKEND_KEY" == *.tfstate ]] || fail "backend key must end in .tfstate"
[[ "$BACKEND_AAD_AUTH" == "true" ]] || fail "backend must use Azure AD authentication"
if grep -Eq '^[[:space:]]*access_key[[:space:]]*=' "$BACKEND_CONFIG"; then
  fail "backend config must not contain a static access key"
fi

grep -rEq --include='*.tf' 'backend[[:space:]]+"azurerm"' "$TERRAFORM_ROOT" \
  || fail "Terraform root must use the azurerm backend with Azure Blob lease locking"

"$AZ_BIN" storage account show \
  --resource-group "$BACKEND_RESOURCE_GROUP" \
  --name "$BACKEND_STORAGE_ACCOUNT" \
  --output json >"$TMP_DIR/storage-account.json"
jq -e \
  --arg name "$BACKEND_STORAGE_ACCOUNT" \
  --arg resource_group "$BACKEND_RESOURCE_GROUP" '
    .name == $name and .resourceGroup == $resource_group and
    (.enableHttpsTrafficOnly == true)
  ' "$TMP_DIR/storage-account.json" >/dev/null \
  || fail "Azure backend storage account does not match or does not require HTTPS"

"$AZ_BIN" storage container show \
  --account-name "$BACKEND_STORAGE_ACCOUNT" \
  --name "$BACKEND_CONTAINER" \
  --auth-mode login \
  --output json >"$TMP_DIR/container.json"
jq -e --arg name "$BACKEND_CONTAINER" \
  '.name == $name and (.properties.publicAccess == null)' \
  "$TMP_DIR/container.json" >/dev/null \
  || fail "Azure backend container is missing or publicly accessible"

"$AZ_BIN" aks get-versions --location "$AZURE_LOCATION" --output json \
  >"$TMP_DIR/aks-versions.json"
jq -e '
  ([.values[]?.version, .orchestrators[]?.orchestratorVersion] |
    map(select(type == "string" and startswith("1.35."))) |
    length) > 0
' "$TMP_DIR/aks-versions.json" >/dev/null \
  || fail "AKS 1.35 is not available in AZURE_LOCATION"

mkdir -p "$(dirname "$OUTPUT")"
jq -n \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg azure_cli_version "$ACTUAL_AZURE_CLI_VERSION" \
  --arg azure_cli_sha256 "$PINNED_AZURE_CLI_SHA256" \
  --arg subscription_id "$ACTUAL_SUBSCRIPTION" \
  --arg tenant_id_hash "$TENANT_ID_HASH" \
  --arg location "$AZURE_LOCATION" \
  --arg candidate_vnet_cidr "$CANDIDATE_VNET_CIDR" \
  --arg backend_resource_group "$BACKEND_RESOURCE_GROUP" \
  --arg backend_storage_account "$BACKEND_STORAGE_ACCOUNT" \
  --arg backend_container "$BACKEND_CONTAINER" \
  --arg backend_key "$BACKEND_KEY" \
  --argjson required_providers "$REQUIRED_PROVIDERS" '
  {
    generatedAt: $generated_at,
    result: "pass",
    azureCliVersion: $azure_cli_version,
    azureCliArtifactSha256: $azure_cli_sha256,
    subscriptionId: $subscription_id,
    tenantIdHash: $tenant_id_hash,
    location: $location,
    candidateVnetCidr: $candidate_vnet_cidr,
    cidrCollision: false,
    providers: {
      required: $required_providers,
      registered: true
    },
    backend: {
      type: "azurerm",
      resourceGroup: $backend_resource_group,
      storageAccount: $backend_storage_account,
      container: $backend_container,
      key: $backend_key,
      authentication: "azuread",
      lockingEnabled: true,
      lockingMechanism: "azure-blob-lease"
    },
    aks: {
      requiredMinor: "1.35",
      available: true
    }
  }
' >"$TMP_DIR/output.json"

mv "$TMP_DIR/output.json" "$OUTPUT"
printf 'PASS: Azure DR preflight wrote redacted evidence to %s\n' "$OUTPUT"
