#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_ROOT="$ROOT_DIR/.aws-profile-plans"
GITOPS_DIR="$(cd "$ROOT_DIR/.." && pwd)/microservice-app-gitops"
EXPECTED_TERRAFORM_VERSION="$(tr -d '[:space:]' <"$ROOT_DIR/.terraform-version")"
DURABLE_DELETE_FILTER="$ROOT_DIR/scripts/aws-profile-durable-deletes.jq"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/aws-profile-lifecycle.sh check {economical|full}
  scripts/aws-profile-lifecycle.sh init {economical|full}
  scripts/aws-profile-lifecycle.sh plan {economical|full} {up|down} [--gitops-revision REVISION]
  scripts/aws-profile-lifecycle.sh inspect BUNDLE_DIRECTORY
  scripts/aws-profile-lifecycle.sh apply {economical|full} {up|down} BUNDLE_DIRECTORY
  scripts/aws-profile-lifecycle.sh status {economical|full}

Planning never applies. Applying accepts only an unchanged saved-plan bundle.
A down plan requires the commit of a reviewed, merged GitOps quiescence change.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_file() {
  [[ -f "$1" ]] || fail "Missing local configuration: $1"
}

validate_profile() {
  case "$1" in
    economical | full) ;;
    *) fail "Unknown profile '$1'; expected economical or full." ;;
  esac
}

validate_direction() {
  case "$1" in
    up | down) ;;
    *) fail "Unknown direction '$1'; expected up or down." ;;
  esac
}

# Records are name|root|backend|variables|kind. The order is the apply order.
profile_records() {
  local profile=$1
  local direction=${2:-up}

  if [[ "$profile" == "economical" ]]; then
    printf '%s\n' 'dev|aws/environments/dev/foundation|dev.s3.tfbackend|dev.tfvars|foundation'
    return
  fi

  if [[ "$direction" == "up" ]]; then
    printf '%s\n' \
      'egress|aws/shared/egress|egress.s3.tfbackend|egress.tfvars|egress' \
      'full-dev|aws/environments/full-dev/foundation|full-dev.s3.tfbackend|full-dev.tfvars|foundation' \
      'demo-full|aws/environments/demo-full/foundation|demo-full.s3.tfbackend|demo-full.tfvars|foundation' \
      'full-prod|aws/environments/full-prod/foundation|full-prod.s3.tfbackend|full-prod.tfvars|foundation'
  else
    printf '%s\n' \
      'full-prod|aws/environments/full-prod/foundation|full-prod.s3.tfbackend|full-prod.tfvars|foundation' \
      'demo-full|aws/environments/demo-full/foundation|demo-full.s3.tfbackend|demo-full.tfvars|foundation' \
      'full-dev|aws/environments/full-dev/foundation|full-dev.s3.tfbackend|full-dev.tfvars|foundation' \
      'egress|aws/shared/egress|egress.s3.tfbackend|egress.tfvars|egress'
  fi
}

read_expected_account() {
  local variables_file=$1
  local account
  account="$(sed -n 's/^[[:space:]]*expected_account_id[[:space:]]*=[[:space:]]*"\([0-9][0-9]*\)"[[:space:]]*$/\1/p' "$variables_file" | tail -n 1)"
  [[ "$account" =~ ^[0-9]{12}$ ]] || fail "No literal 12-digit expected_account_id was found in $variables_file."
  printf '%s\n' "$account"
}

read_literal_string() {
  local variables_file=$1
  local variable_name=$2
  sed -n "s/^[[:space:]]*${variable_name}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\"[[:space:]]*$/\\1/p" "$variables_file" | tail -n 1
}

caller_account() {
  aws sts get-caller-identity --query Account --output text
}

verify_toolchain() {
  require_command terraform
  require_command aws
  require_command git
  require_command jq
  require_command grep
  require_command sha256sum

  local actual_version
  actual_version="$(terraform version -json | jq -r '.terraform_version')"
  [[ "$actual_version" == "$EXPECTED_TERRAFORM_VERSION" ]] || \
    fail "Terraform $EXPECTED_TERRAFORM_VERSION is required; found $actual_version."
  [[ "$(aws --version 2>&1)" == aws-cli/2.* ]] || fail "AWS CLI v2 is required."
  [[ -n "${AWS_PROFILE:-}" ]] || fail "AWS_PROFILE must select an approved short-lived role profile."
}

verify_git_clean() {
  git -C "$ROOT_DIR" diff --quiet || fail "Tracked working-tree changes must be committed before creating or applying a saved plan."
  git -C "$ROOT_DIR" diff --cached --quiet || fail "Staged changes must be committed before creating or applying a saved plan."
}

verify_gitops_revision() {
  local revision=$1
  [[ "$revision" =~ ^[0-9a-f]{7,40}$ ]] || fail "A down plan requires --gitops-revision with a Git commit SHA."
  [[ -d "$GITOPS_DIR/.git" ]] || fail "GitOps repository not found at $GITOPS_DIR."
  git -C "$GITOPS_DIR" cat-file -e "${revision}^{commit}" 2>/dev/null || \
    fail "GitOps revision $revision is not available in the local GitOps repository."
  git -C "$GITOPS_DIR" merge-base --is-ancestor "$revision" origin/main || \
    fail "GitOps revision $revision is not merged into the locally known origin/main. Fetch the GitOps repository and retry."
}

verify_profile() {
  local profile=$1
  local direction=${2:-up}
  local active_account
  local common_account=""
  local name relative_root backend_name variables_name kind root backend_file variables_file expected_account

  verify_toolchain
  active_account="$(caller_account)"
  [[ "$active_account" =~ ^[0-9]{12}$ ]] || fail "AWS STS did not return a valid account id. Renew the AWS login and retry."

  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    root="$ROOT_DIR/$relative_root"
    backend_file="$root/$backend_name"
    variables_file="$root/$variables_name"
    require_file "$backend_file"
    require_file "$variables_file"
    expected_account="$(read_expected_account "$variables_file")"

    [[ "$expected_account" == "$active_account" ]] || \
      fail "$name targets AWS account $expected_account but the active session is $active_account."
    if [[ -n "$common_account" && "$common_account" != "$expected_account" ]]; then
      fail "$profile mixes AWS accounts $common_account and $expected_account."
    fi
    common_account="$expected_account"

    printf 'READY  %-12s account=%s root=%s\n' "$name" "$expected_account" "$relative_root"
  done < <(profile_records "$profile" "$direction")
}

init_root() {
  local root=$1
  local backend_file=$2
  terraform -chdir="$root" init \
    -input=false \
    -reconfigure \
    -backend-config="$backend_file" \
    -lockfile=readonly
}

init_profile() {
  local profile=$1
  local name relative_root backend_name variables_name kind root
  verify_profile "$profile" up

  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    root="$ROOT_DIR/$relative_root"
    printf 'Initializing %s...\n' "$name"
    init_root "$root" "$root/$backend_name"
  done < <(profile_records "$profile" up)
}

assert_no_durable_deletes() {
  local plan_json=$1
  local deleted
  require_file "$DURABLE_DELETE_FILTER"
  deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" "$plan_json")"
  [[ -z "$deleted" ]] || fail "Saved shutdown plan attempts to delete durable resources: ${deleted//$'\n'/, }."
}

plan_profile() {
  local profile=$1
  local direction=$2
  local gitops_revision=$3
  local timestamp bundle active_account commit
  local name relative_root backend_name variables_name kind root plan_file json_file
  local configured_transit_gateway full_up_egress_only=false transit_gateway_id="" state_before
  local -a plan_args

  verify_git_clean
  verify_profile "$profile" "$direction"
  if [[ "$direction" == "down" ]]; then
    verify_gitops_revision "$gitops_revision"
  fi

  active_account="$(caller_account)"
  commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  bundle="$PLAN_ROOT/${profile}-${direction}-${timestamp}"
  mkdir -p "$bundle"
  chmod 700 "$PLAN_ROOT" "$bundle"
  umask 077

  {
    printf 'format\t1\n'
    printf 'profile\t%s\n' "$profile"
    printf 'direction\t%s\n' "$direction"
    printf 'account\t%s\n' "$active_account"
    printf 'commit\t%s\n' "$commit"
    printf 'gitops_revision\t%s\n' "$gitops_revision"
  } >"$bundle/metadata.tsv"

  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    root="$ROOT_DIR/$relative_root"
    plan_file="$bundle/$name.tfplan"
    json_file="$bundle/$name.json"

    printf 'Planning %s %s for %s...\n' "$profile" "$direction" "$name"
    init_root "$root" "$root/$backend_name"

    if [[ "$profile" == "full" && "$direction" == "up" && "$name" == "egress" ]]; then
      state_before="$(terraform -chdir="$root" state list 2>/dev/null || true)"
      if ! grep -Eq 'module\.egress' <<<"$state_before"; then
        full_up_egress_only=true
      else
        transit_gateway_id="$(terraform -chdir="$root" output -raw transit_gateway_id)"
        [[ "$transit_gateway_id" =~ ^tgw-[0-9a-f]{8,17}$ ]] || \
          fail "The existing egress state did not expose a valid transit_gateway_id."
      fi
    fi

    if [[ "$profile" == "full" && "$direction" == "up" && ( "$name" == "full-dev" || "$name" == "full-prod" ) ]]; then
      configured_transit_gateway="$(read_literal_string "$root/$variables_name" transit_gateway_id)"
      [[ "$configured_transit_gateway" == "$transit_gateway_id" ]] || \
        fail "$name configures transit_gateway_id=${configured_transit_gateway:-missing}, but the egress state exposes $transit_gateway_id."
    fi

    plan_args=(
      -input=false
      -lock-timeout=5m
      -var-file="$root/$variables_name"
      -out="$plan_file"
    )

    if [[ "$kind" == "foundation" ]]; then
      if [[ "$direction" == "up" ]]; then
        plan_args+=("-var=runtime_enabled=true")
      else
        plan_args+=("-var=runtime_enabled=false")
      fi
      terraform -chdir="$root" plan "${plan_args[@]}"
    elif [[ "$direction" == "down" ]]; then
      terraform -chdir="$root" plan -destroy "${plan_args[@]}"
    else
      terraform -chdir="$root" plan "${plan_args[@]}"
    fi

    terraform -chdir="$root" show -json "$plan_file" >"$json_file"
    if [[ "$direction" == "down" && "$kind" == "foundation" ]]; then
      assert_no_durable_deletes "$json_file"
    fi
    printf 'root\t%s\t%s\t%s\n' "$name" "$relative_root" "$name.tfplan" >>"$bundle/metadata.tsv"

    if [[ "$full_up_egress_only" == true ]]; then
      printf 'The full egress hub has no prior state; this bundle intentionally contains only egress.\n'
      printf 'Apply it, record its transit_gateway_id in the full foundation inputs, then run full up planning again.\n'
      break
    fi
  done < <(profile_records "$profile" "$direction")

  (
    cd "$bundle"
    sha256sum ./*.tfplan ./*.json metadata.tsv >checksums.sha256
  )
  printf 'Saved plan bundle: %s\n' "$bundle"
  printf 'Inspect it before apply: %s inspect %s\n' "$0" "$bundle"
}

metadata_value() {
  local bundle=$1
  local key=$2
  awk -F '\t' -v key="$key" '$1 == key { print $2; exit }' "$bundle/metadata.tsv"
}

inspect_bundle() {
  local bundle=$1
  local name relative_root plan_name
  require_file "$bundle/metadata.tsv"
  require_file "$bundle/checksums.sha256"
  (cd "$bundle" && sha256sum -c checksums.sha256)

  printf 'Profile: %s\n' "$(metadata_value "$bundle" profile)"
  printf 'Direction: %s\n' "$(metadata_value "$bundle" direction)"
  printf 'Account: %s\n' "$(metadata_value "$bundle" account)"
  printf 'Commit: %s\n' "$(metadata_value "$bundle" commit)"
  printf 'GitOps revision: %s\n' "$(metadata_value "$bundle" gitops_revision)"

  while IFS=$'\t' read -r marker name relative_root plan_name; do
    [[ "$marker" == "root" ]] || continue
    printf '\n=== %s (%s) ===\n' "$name" "$relative_root"
    terraform -chdir="$ROOT_DIR/$relative_root" show "$bundle/$plan_name"
  done <"$bundle/metadata.tsv"
}

backup_state() {
  local name=$1
  local root=$2
  local account=$3
  local timestamp user_home backup_dir state_file receipt
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  user_home="$(getent passwd "$(id -un)" | cut -d: -f6)"
  [[ -n "$user_home" ]] || fail "Could not resolve the current user's home directory for the external state backup."
  backup_dir="$user_home/backups-microtodosuite/$account/$timestamp"
  mkdir -p "$backup_dir"
  chmod 700 "$user_home/backups-microtodosuite" "$user_home/backups-microtodosuite/$account" "$backup_dir"
  state_file="$backup_dir/$name.tfstate"
  receipt="$backup_dir/$name.no-prior-state.txt"

  if terraform -chdir="$root" state pull >"$state_file" 2>/dev/null; then
    chmod 600 "$state_file"
    printf 'State backup: %s\n' "$state_file"
  else
    rm -f "$state_file"
    printf 'No prior state was returned for %s at %s.\n' "$name" "$timestamp" >"$receipt"
    chmod 600 "$receipt"
    printf 'No-prior-state receipt: %s\n' "$receipt"
  fi
}

apply_bundle() {
  local requested_profile=$1
  local requested_direction=$2
  local bundle=$3
  local stored_profile stored_direction stored_account stored_commit active_account
  local name relative_root plan_name root

  verify_toolchain
  verify_git_clean
  require_file "$bundle/metadata.tsv"
  require_file "$bundle/checksums.sha256"
  stored_profile="$(metadata_value "$bundle" profile)"
  stored_direction="$(metadata_value "$bundle" direction)"
  stored_account="$(metadata_value "$bundle" account)"
  stored_commit="$(metadata_value "$bundle" commit)"
  active_account="$(caller_account)"

  [[ "$stored_profile" == "$requested_profile" ]] || fail "Bundle profile is $stored_profile, not $requested_profile."
  [[ "$stored_direction" == "$requested_direction" ]] || fail "Bundle direction is $stored_direction, not $requested_direction."
  [[ "$stored_account" == "$active_account" ]] || fail "Bundle account is $stored_account but AWS STS reports $active_account."
  [[ "$stored_commit" == "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]] || fail "The checked-out commit differs from the plan bundle commit. Re-plan."
  if [[ "$requested_direction" == "down" ]]; then
    verify_gitops_revision "$(metadata_value "$bundle" gitops_revision)"
  fi
  (cd "$bundle" && sha256sum -c checksums.sha256)

  while IFS=$'\t' read -r marker name relative_root plan_name; do
    [[ "$marker" == "root" ]] || continue
    root="$ROOT_DIR/$relative_root"
    require_file "$bundle/$plan_name"
    backup_state "$name" "$root" "$stored_account"
    printf 'Applying reviewed saved plan for %s...\n' "$name"
    terraform -chdir="$root" apply -input=false "$bundle/$plan_name"
  done <"$bundle/metadata.tsv"
}

status_profile() {
  local profile=$1
  local name relative_root backend_name variables_name kind root state
  verify_profile "$profile" up

  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    root="$ROOT_DIR/$relative_root"
    init_root "$root" "$root/$backend_name" >/dev/null
    state="$(terraform -chdir="$root" state list 2>/dev/null || true)"
    if [[ "$kind" == "foundation" ]] && grep -Eq 'module\.foundation\.module\.eks' <<<"$state"; then
      printf 'UP    %s\n' "$name"
    elif [[ "$kind" == "egress" ]] && grep -Eq 'module\.egress' <<<"$state"; then
      printf 'UP    %s\n' "$name"
    else
      printf 'DOWN  %s\n' "$name"
    fi
  done < <(profile_records "$profile" up)
}

command=${1:-}
case "$command" in
  check)
    profile=${2:-}
    validate_profile "$profile"
    verify_profile "$profile" up
    ;;
  init)
    profile=${2:-}
    validate_profile "$profile"
    init_profile "$profile"
    ;;
  plan)
    profile=${2:-}
    direction=${3:-}
    validate_profile "$profile"
    validate_direction "$direction"
    gitops_revision=""
    if [[ "$direction" == "down" ]]; then
      [[ "${4:-}" == "--gitops-revision" && -n "${5:-}" && -z "${6:-}" ]] || { usage; exit 2; }
      gitops_revision=$5
    else
      [[ -z "${4:-}" ]] || { usage; exit 2; }
    fi
    plan_profile "$profile" "$direction" "$gitops_revision"
    ;;
  inspect)
    [[ -n "${2:-}" && -z "${3:-}" ]] || { usage; exit 2; }
    inspect_bundle "$2"
    ;;
  apply)
    profile=${2:-}
    direction=${3:-}
    bundle=${4:-}
    validate_profile "$profile"
    validate_direction "$direction"
    [[ -n "$bundle" && -z "${5:-}" ]] || { usage; exit 2; }
    apply_bundle "$profile" "$direction" "$bundle"
    ;;
  status)
    profile=${2:-}
    validate_profile "$profile"
    status_profile "$profile"
    ;;
  *)
    usage
    exit 2
    ;;
esac
