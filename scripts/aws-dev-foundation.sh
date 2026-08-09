#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FOUNDATION_DIR="$ROOT_DIR/aws/environments/dev/foundation"
MODULE_DIR="$ROOT_DIR/aws/modules/environment-foundation"
BACKEND_FILE="$FOUNDATION_DIR/dev.s3.tfbackend"
TFVARS_FILE="$FOUNDATION_DIR/dev.tfvars"
EXPECTED_TERRAFORM_VERSION="1.15.8"

usage() {
  printf 'Usage: %s {check|init|validate|test|plan|cost}\n' "$0" >&2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

require_local_file() {
  [[ -f "$1" ]] || {
    printf 'Missing local configuration: %s\n' "$1" >&2
    exit 1
  }
}

check_prerequisites() {
  require_command terraform
  require_command aws
  require_command rg

  local terraform_version
  terraform_version="$(terraform version -json | sed -n 's/.*"terraform_version":"\([^"]*\)".*/\1/p')"
  if [[ "$terraform_version" != "$EXPECTED_TERRAFORM_VERSION" ]]; then
    printf 'Terraform %s is required; found %s.\n' "$EXPECTED_TERRAFORM_VERSION" "${terraform_version:-unknown}" >&2
    exit 1
  fi

  if [[ "$(aws --version 2>&1)" != aws-cli/2.* ]]; then
    printf 'AWS CLI v2 is required.\n' >&2
    exit 1
  fi

  if [[ -z "${AWS_PROFILE:-}" ]]; then
    printf 'AWS_PROFILE must select the approved short-lived or federated profile.\n' >&2
    exit 1
  fi

  require_local_file "$TFVARS_FILE"
  require_local_file "$BACKEND_FILE"

  aws sts get-caller-identity --output json >/dev/null
  terraform fmt -check -recursive "$ROOT_DIR/aws"
  "$ROOT_DIR/tests/contract/aws-dev-foundation.sh"

  if rg -n --hidden --glob '!*.example' --glob '!*.tfstate*' \
    '(AKIA[0-9A-Z]{16}|AWS_SECRET_ACCESS_KEY[[:space:]]*=)' \
    "$ROOT_DIR/aws" "$ROOT_DIR/scripts/aws-dev-foundation.sh" >/dev/null; then
    printf 'Potential static AWS credential material detected.\n' >&2
    exit 1
  fi

  printf 'AWS dev foundation prerequisites verified.\n'
}

case "${1:-}" in
  check)
    check_prerequisites
    ;;
  init)
    require_local_file "$BACKEND_FILE"
    terraform -chdir="$FOUNDATION_DIR" init \
      -input=false \
      -backend-config="$BACKEND_FILE" \
      -lockfile=readonly
    ;;
  validate)
    terraform -chdir="$FOUNDATION_DIR" validate
    ;;
  test)
    terraform -chdir="$MODULE_DIR" init -backend=false -input=false -lockfile=readonly
    terraform -chdir="$MODULE_DIR" test
    terraform -chdir="$FOUNDATION_DIR" test
    "$ROOT_DIR/tests/contract/aws-dev-foundation.sh"
    ;;
  plan)
    require_local_file "$TFVARS_FILE"
    terraform -chdir="$FOUNDATION_DIR" plan \
      -input=false \
      -lock-timeout=5m \
      -var-file="$TFVARS_FILE"
    ;;
  cost)
    require_command infracost
    require_local_file "$TFVARS_FILE"
    infracost breakdown \
      --path "$FOUNDATION_DIR" \
      --terraform-var-file "$TFVARS_FILE"
    ;;
  *)
    usage
    exit 2
    ;;
esac
