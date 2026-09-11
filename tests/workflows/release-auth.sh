#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/release.yml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_text() {
  local expected=$1
  local message=$2
  grep -Fq -- "$expected" "$WORKFLOW" || fail "$message"
}

[[ -f "$WORKFLOW" ]] || fail "missing release workflow"

require_text 'contents: write' \
  "release job must be allowed to publish repository contents"
require_text 'issues: write' \
  "release job must be allowed to update release issues"
require_text 'pull-requests: write' \
  "release job must be allowed to update release pull requests"
require_text 'fetch-depth: 0' \
  "release checkout must fetch the full history used by semantic-release"
require_text 'GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}' \
  "semantic-release must use the repository-scoped GitHub Actions token"

if grep -Fq -- 'secrets.GH_TOKEN' "$WORKFLOW"; then
  fail "release workflow must not depend on the invalid custom GH_TOKEN secret"
fi

printf 'PASS: release workflow uses the repository-scoped token and explicit permissions.\n'
