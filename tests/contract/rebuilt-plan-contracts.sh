#!/usr/bin/env bash
# Checks saved plan JSON for every rebuilt environment root. The operator
# supplies a directory with one <environment>/<domain>.json file per root.
# --self-test proves the contract with committed synthetic plans and no AWS
# access.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURES="$ROOT/tests/contract/fixtures/rebuilt-plans"
WORKFLOW="$ROOT/.github/workflows/iac-checks.yml"
CONTRACT_REPOSITORY="https://github.com/MicroTodoSuite/.github.git"

failures=0
checker_ready=false
temporary_directory=""
checker_python=""
checker_script=""

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

die() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 2
}

cleanup() {
  if [[ -n "$temporary_directory" && -d "$temporary_directory" ]]; then
    rm -rf -- "$temporary_directory"
  fi
}
trap cleanup EXIT

contract_commit() {
  local commits
  commits="$(sed -nE 's#.*MicroTodoSuite/\.github/\.github/workflows/iac-checks\.yml@([0-9a-f]{40}).*#\1#p' "$WORKFLOW")"
  [[ "$commits" =~ ^[0-9a-f]{40}$ ]] || die "$WORKFLOW must pin exactly one full .github iac-checks commit"
  printf '%s\n' "$commits"
}

prepare_checker() {
  local commit
  [[ "$checker_ready" == true ]] && return

  command -v git >/dev/null 2>&1 || die "git is required"
  command -v python3 >/dev/null 2>&1 || die "python3 is required"

  commit="$(contract_commit)"
  temporary_directory="$(mktemp -d)"

  git init --quiet "$temporary_directory/contracts"
  git -C "$temporary_directory/contracts" remote add origin "$CONTRACT_REPOSITORY"
  git -C "$temporary_directory/contracts" fetch --quiet --depth 1 origin "$commit"
  git -C "$temporary_directory/contracts" checkout --quiet --detach FETCH_HEAD

  python3 -m venv "$temporary_directory/venv"
  "$temporary_directory/venv/bin/pip" install --quiet --require-hashes -r "$temporary_directory/contracts/scripts/iac/requirements.txt"

  checker_python="$temporary_directory/venv/bin/python"
  checker_script="$temporary_directory/contracts/scripts/iac/contracts.py"
  checker_ready=true
}

check_module_sources() {
  local plan=$1
  python3 - "$plan" <<'PY'
import json
import re
import sys
from pathlib import Path

plan_path = Path(sys.argv[1])
plan = json.loads(plan_path.read_text(encoding="utf-8"))
pattern = re.compile(
    r"^git::https://github\.com/MicroTodoSuite/terraform-aws-modules\.git//"
    r"(?P<module>[a-z0-9]+(?:-[a-z0-9]+)*)"
    r"\?ref=(?P=module)-v[0-9]+\.[0-9]+\.[0-9]+$"
)
findings = []
checked = 0

def walk(module):
    global checked
    for name, call in (module or {}).get("module_calls", {}).items():
        checked += 1
        source = call.get("source")
        if not isinstance(source, str) or not pattern.fullmatch(source):
            findings.append(
                f"FAIL MTS-IAC-102 {plan_path} module.{name}: "
                "source must be git::https://github.com/MicroTodoSuite/"
                "terraform-aws-modules.git//<module>?ref=<module>-vX.Y.Z"
            )
        child = call.get("module")
        if isinstance(child, dict):
            walk(child)

walk(plan.get("configuration", {}).get("root_module", {}))
if checked == 0:
    findings.append(
        f"FAIL MTS-IAC-102 {plan_path}: plan configuration contains no module calls"
    )
for finding in findings:
    print(finding)
if findings:
    raise SystemExit(1)
print(f"module-source-contract: {checked} call(s) checked")
PY
}

check_plan() {
  local plan=$1
  local domain=$2
  local result=0

  prepare_checker
  "$checker_python" "$checker_script" plan "$plan" --client lex --project mts --domain "$domain" || result=1
  check_module_sources "$plan" || result=1
  return "$result"
}

expect_pass() {
  local label=$1
  local domain=$2
  local plan=$3
  local output
  output="$(mktemp)"

  if check_plan "$plan" "$domain" >"$output" 2>&1; then
    printf 'PASS fixture: %s\n' "$label"
  else
    cat "$output" >&2
    fail "fixture expected to pass: $label"
  fi
  rm -f -- "$output"
}

expect_fail() {
  local label=$1
  local domain=$2
  local plan=$3
  local expected=$4
  local output
  output="$(mktemp)"

  if check_plan "$plan" "$domain" >"$output" 2>&1; then
    fail "fixture expected to fail: $label"
  elif grep -Fq -- "$expected" "$output"; then
    printf 'MUTATION fixture: %s -> %s\n' "$label" "$expected"
  else
    cat "$output" >&2
    fail "fixture $label failed without the expected $expected finding"
  fi
  rm -f -- "$output"
}

expect_domain_mapping() {
  local root_domain=$1
  local expected_contract_domain=$2
  local actual_contract_domain=""

  if actual_contract_domain="$(contract_domain "$root_domain" 2>/dev/null)"; then
    if [[ "$actual_contract_domain" == "$expected_contract_domain" ]]; then
      printf 'PASS domain mapping: %s -> %s\n' "$root_domain" "$expected_contract_domain"
      return
    fi
  fi
  fail "$root_domain must map to the $expected_contract_domain plan domain"
}

self_test() {
  expect_pass "state domain" state "$FIXTURES/pass/state.json"
  expect_pass "security domain" security "$FIXTURES/pass/security.json"
  expect_pass "registry domain" registry "$FIXTURES/pass/registry.json"
  expect_pass "dns domain" dns "$FIXTURES/pass/dns.json"
  expect_pass "networking domain" networking "$FIXTURES/pass/networking.json"
  expect_pass "workload domain" workload "$FIXTURES/pass/workload.json"

  expect_fail "non-conforming physical name" networking "$FIXTURES/fail/naming.json" "PC-IAC-003"
  expect_fail "missing transversal tag" networking "$FIXTURES/fail/tags.json" "PC-IAC-004"
  expect_fail "resource outside the root domain" security "$FIXTURES/fail/domain.json" "PC-IAC-022"
  expect_fail "unpinned module source" networking "$FIXTURES/fail/module-source.json" "MTS-IAC-102"
  expect_domain_mapping "security-irsa" "security"

  if ((failures > 0)); then
    printf 'FAIL: %d rebuilt-plan fixture check(s) failed\n' "$failures" >&2
    return 1
  fi
  echo "rebuilt-plan-contracts self-test: PASS (10 fixtures, 1 domain mapping)"
}

valid_environment() {
  case "$1" in
    shd | eco | fdev | fstg | fprd) return 0 ;;
    *) return 1 ;;
  esac
}

contract_domain() {
  case "$1" in
    security-irsa) printf 'security\n' ;;
    state | security | registry | dns | networking | workload) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

check_operator_plans() {
  local plan_directory=$1
  local root
  local environment
  local root_domain
  local domain
  local plan
  local roots=0

  [[ -d "$plan_directory" ]] || die "plan directory does not exist: $plan_directory"
  plan_directory="$(cd "$plan_directory" && pwd)"

  while IFS= read -r root; do
    environment="$(basename "$(dirname "$root")")"
    root_domain="$(basename "$root")"
    valid_environment "$environment" || continue
    roots=$((roots + 1))

    if ! domain="$(contract_domain "$root_domain")"; then
      fail "unsupported rebuilt root domain: aws/environments/$environment/$root_domain"
      continue
    fi

    plan="$plan_directory/$environment/$root_domain.json"
    if [[ ! -f "$plan" ]]; then
      fail "missing plan JSON for aws/environments/$environment/$root_domain at $plan"
      continue
    fi

    echo "=== aws/environments/$environment/$root_domain ==="
    check_plan "$plan" "$domain" || failures=$((failures + 1))
  done < <(
    find "$ROOT/aws/environments" -mindepth 2 -maxdepth 2 -type d -exec sh -c 'find "$1" -maxdepth 1 -type f -name "*.tf" -print -quit | grep -q .' _ {} \; -print | sort
  )

  ((roots > 0)) || fail "no rebuilt roots were found under aws/environments"
  if ((failures > 0)); then
    printf 'FAIL: %d rebuilt-plan contract check(s) failed\n' "$failures" >&2
    return 1
  fi
  printf 'rebuilt-plan-contracts: PASS (%d roots)\n' "$roots"
}

case "${1:-}" in
  --self-test)
    [[ $# -eq 1 ]] || die "usage: $0 --self-test"
    self_test
    ;;
  "")
    die "usage: $0 <plan-directory> | --self-test"
    ;;
  *)
    [[ $# -eq 1 ]] || die "usage: $0 <plan-directory> | --self-test"
    check_operator_plans "$1"
    ;;
esac
