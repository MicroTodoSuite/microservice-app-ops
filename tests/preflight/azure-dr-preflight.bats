#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/preflight/azure-dr.sh"
FIXTURES="$ROOT/tests/preflight/fixtures"
EXPECTED_SUBSCRIPTION="11111111-1111-1111-1111-111111111111"
EXPECTED_TENANT="22222222-2222-2222-2222-222222222222"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

prepare_fixture() {
  local name="$1"
  local destination="$TMP_DIR/$name"
  cp -R "$FIXTURES/valid/." "$destination"
  if [[ "$name" != "valid" ]]; then
    cp -R "$FIXTURES/$name/." "$destination"
  fi
  printf '%s\n' "$destination"
}

run_preflight() {
  local fixture="$1" output="$2"
  AZURE_DR_FIXTURE_DIR="$fixture" \
  AZURE_SUBSCRIPTION_ID_COLONIA="$EXPECTED_SUBSCRIPTION" \
  AZURE_LOCATION="eastus" \
  PATH="$FIXTURES/valid/bin:$PATH" \
    "$SCRIPT" \
      --candidate-vnet-cidr "10.50.0.0/16" \
      --backend-config "$fixture/backend.tfbackend" \
      --terraform-root "$fixture/terraform-root" \
      --output "$output"
}

[[ -x "$SCRIPT" ]] || fail "preflight script is missing or not executable: $SCRIPT"

if AZURE_SUBSCRIPTION_ID_COLONIA="$EXPECTED_SUBSCRIPTION" \
  AZURE_LOCATION="eastus" PATH="/usr/bin:/bin" \
  bash "$SCRIPT" --candidate-vnet-cidr "10.50.0.0/16" \
    --backend-config "$FIXTURES/valid/backend.tfbackend" \
    --terraform-root "$FIXTURES/valid/terraform-root" \
    --output "$TMP_DIR/missing-cli.json" >/dev/null 2>&1; then
  fail "missing Azure CLI did not fail closed"
fi

for scenario in wrong-subscription cidr-collision missing-provider missing-backend-locking
do
  fixture="$(prepare_fixture "$scenario")"
  if run_preflight "$fixture" "$TMP_DIR/$scenario.json" >/dev/null 2>&1; then
    fail "$scenario did not fail closed"
  fi
done

valid_fixture="$(prepare_fixture valid)"
run_preflight "$valid_fixture" "$TMP_DIR/valid.json"

jq -e '
  .result == "pass" and
  .azureCliVersion == "2.89.1" and
  .subscriptionId == "11111111-1111-1111-1111-111111111111" and
  .location == "eastus" and
  .candidateVnetCidr == "10.50.0.0/16" and
  .backend.lockingEnabled == true and
  .backend.lockingMechanism == "azure-blob-lease" and
  .providers.registered == true and
  .cidrCollision == false
' "$TMP_DIR/valid.json" >/dev/null

if rg -q "$EXPECTED_TENANT|fixture@example.invalid" "$TMP_DIR/valid.json"; then
  fail "preflight output exposed tenant or user identity"
fi

printf 'PASS: Azure DR preflight fails closed and redacts identity output\n'
