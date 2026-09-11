#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAKEFILE="$ROOT/Makefile"
WORKFLOW="$ROOT/.github/workflows/aws-dev-foundation-checks.yml"
LIFECYCLE='./scripts/aws-profile-lifecycle.sh'

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_output() {
  local output=$1
  local expected=$2
  local message=$3
  grep -Fq -- "$expected" <<<"$output" || fail "$message"
}

reject_makefile_text() {
  local pattern=$1
  local message=$2
  if grep -En -- "$pattern" "$MAKEFILE" >/dev/null; then
    fail "$message"
  fi
}

require_file_text() {
  local file=$1
  local expected=$2
  local message=$3
  grep -Fq -- "$expected" "$file" || fail "$message"
}

dry_run() {
  make --no-print-directory --silent --dry-run -C "$ROOT" "$@"
}

require_single_wrapper_command() {
  local output=$1
  local expected=$2
  local message=$3
  local count
  require_output "$output" "$expected" "$message"
  count="$(grep -Fc -- "$LIFECYCLE" <<<"$output")"
  [[ "$count" == 1 ]] || fail "${message}; expected exactly one wrapper command, found $count"
}

command -v make >/dev/null 2>&1 || fail "GNU Make is required for the operator interface contract"
[[ -f "$MAKEFILE" ]] || fail "missing file: Makefile"
[[ -f "$WORKFLOW" ]] || fail "missing AWS foundation workflow"

require_file_text "$WORKFLOW" "- 'Makefile'" \
  "AWS foundation workflow must run when the Makefile changes"
require_file_text "$WORKFLOW" "- 'tests/contract/aws-profile-lifecycle-make.sh'" \
  "AWS foundation workflow must run when the Make contract changes"
require_file_text "$WORKFLOW" './tests/contract/aws-profile-lifecycle-make.sh' \
  "AWS foundation workflow must execute the Make interface contract"

reject_makefile_text '(^|[[:space:]])(terraform|kubectl)([[:space:]]|$)' \
  "Makefile must not invoke Terraform or kubectl directly"
reject_makefile_text 'auto-approve' \
  "Makefile must not expose auto-approval"
reject_makefile_text 'PROFILE[[:space:]]*\?=[[:space:]]*(economical|full)' \
  "Makefile must not silently select a lifecycle profile"

help_output="$(make --no-print-directory --silent -C "$ROOT" help)"
for target in check init status plan-up plan-down inspect apply-up apply-down; do
  require_output "$help_output" "$target" "help is missing the $target target"
done
require_output "$help_output" 'PROFILE=economical|full' \
  "help must document the two explicit lifecycle profiles"
require_output "$help_output" 'durable' \
  "help must explain that durable resources survive down transitions"

for profile in economical full; do
  for target in check init status; do
    output="$(dry_run "$target" "PROFILE=$profile")"
    require_single_wrapper_command "$output" "$LIFECYCLE $target $profile" \
      "$target must delegate the $profile profile to the wrapper"
  done

  output="$(dry_run plan-up "PROFILE=$profile")"
  require_single_wrapper_command "$output" "$LIFECYCLE plan $profile up" \
    "plan-up must create only the $profile up plan"

  output="$(dry_run plan-down "PROFILE=$profile" GITOPS_REVISION=abcdef1)"
  require_single_wrapper_command "$output" "$LIFECYCLE plan $profile down --gitops-revision \"abcdef1\"" \
    "plan-down must pass GitOps quiescence evidence for $profile"

  output="$(dry_run apply-up "PROFILE=$profile" BUNDLE=.aws-profile-plans/example-up)"
  require_single_wrapper_command "$output" "$LIFECYCLE apply $profile up \".aws-profile-plans/example-up\"" \
    "apply-up must use only the explicit $profile bundle"

  output="$(dry_run apply-down "PROFILE=$profile" BUNDLE=.aws-profile-plans/example-down)"
  require_single_wrapper_command "$output" "$LIFECYCLE apply $profile down \".aws-profile-plans/example-down\"" \
    "apply-down must use only the explicit $profile bundle"
done

output="$(dry_run inspect BUNDLE=.aws-profile-plans/example)"
require_single_wrapper_command "$output" "$LIFECYCLE inspect \".aws-profile-plans/example\"" \
  "inspect must use only the explicit bundle"

if output="$(make --no-print-directory --silent -C "$ROOT" check 2>&1)"; then
  fail "check must reject a missing PROFILE"
fi
require_output "$output" 'PROFILE must be economical or full' \
  "missing PROFILE rejection must be actionable"

if output="$(make --no-print-directory --silent -C "$ROOT" status PROFILE=invalid 2>&1)"; then
  fail "status must reject an invalid PROFILE"
fi
require_output "$output" 'PROFILE must be economical or full' \
  "invalid PROFILE rejection must be actionable"

if output="$(make --no-print-directory --silent -C "$ROOT" inspect 2>&1)"; then
  fail "inspect must reject a missing BUNDLE"
fi
require_output "$output" 'BUNDLE is required' \
  "missing BUNDLE rejection must be actionable"

if output="$(make --no-print-directory --silent -C "$ROOT" plan-down PROFILE=economical 2>&1)"; then
  fail "plan-down must reject a missing GITOPS_REVISION"
fi
require_output "$output" 'GITOPS_REVISION is required' \
  "missing GitOps revision rejection must be actionable"

printf 'PASS: AWS profile lifecycle Make interface contract\n'
