#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_ROOT="$ROOT_DIR/.aws-profile-plans"
EXPECTED_TERRAFORM_VERSION="$(tr -d '[:space:]' <"$ROOT_DIR/.terraform-version")"
DURABLE_DELETE_FILTER="$ROOT_DIR/scripts/aws-profile-durable-deletes.jq"
EGRESS_DELETE_FILTER="$ROOT_DIR/scripts/aws-profile-egress-deletes.jq"
ACCOUNT_FILE="$ROOT_DIR/config/aws-account.env"

usage() {
  cat >&2 <<'EOF'
Usage:
  scripts/aws-profile-lifecycle.sh check {economical|full}
  scripts/aws-profile-lifecycle.sh init {economical|full}
  scripts/aws-profile-lifecycle.sh snapshot-volumes {economical|full} [--consent VOLUME_ID]...
  scripts/aws-profile-lifecycle.sh quiescence-receipt {economical|full} --volume-record RECORD_DIRECTORY
  scripts/aws-profile-lifecycle.sh plan {economical|full} {up|down} [--receipt RECEIPT_DIRECTORY --volume-record RECORD_DIRECTORY]
  scripts/aws-profile-lifecycle.sh inspect BUNDLE_DIRECTORY
  scripts/aws-profile-lifecycle.sh apply {economical|full} {up|down} BUNDLE_DIRECTORY
  scripts/aws-profile-lifecycle.sh status {economical|full}

Planning never applies. Applying accepts only an unchanged saved-plan bundle.
A down plan requires a quiescence receipt produced by quiescence-receipt and
a persistent-volume record that snapshot-volumes wrote before the receipt.
During a down apply, a post-destroy runtime sweep removes controller runtime
resources between the cluster destruction and the first networking apply.
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

canonical_bundle_path() {
  local bundle=$1
  [[ -d "$bundle" ]] || fail "Saved plan bundle does not exist: $bundle."
  (
    cd "$bundle" || exit 1
    pwd -P
  )
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

# Records are name|root|backend|variables|kind, listed in the up order; down is the
# reverse. Only runtime roots appear: shd/state, shd/security, shd/registry, shd/dns,
# and every environment's security root hold the persistent resources and are never
# planned here. A networking root keeps its VPC and switches its NAT egress; a spoke
# keeps its VPC and switches its transit egress; a hub, a cluster root, and an
# identity root (the IRSA pass) are destroyed when the profile goes down.
profile_records() {
  local profile=$1
  local direction=${2:-up}
  local -a records
  local index

  if [[ "$profile" == "economical" ]]; then
    records=(
      'eco-networking|aws/environments/eco/networking|networking.s3.tfbackend|eco.tfvars|networking'
      'eco-workload|aws/environments/eco/workload|workload.s3.tfbackend|eco.tfvars|cluster'
      'eco-security-irsa|aws/environments/eco/security-irsa|security-irsa.s3.tfbackend|eco.tfvars|identity'
    )
  else
    records=(
      'shd-networking|aws/environments/shd/networking|networking.s3.tfbackend|shd.tfvars|hub'
      'fdev-networking|aws/environments/fdev/networking|networking.s3.tfbackend|fdev.tfvars|spoke'
      'fstg-networking|aws/environments/fstg/networking|networking.s3.tfbackend|fstg.tfvars|spoke'
      'fprd-networking|aws/environments/fprd/networking|networking.s3.tfbackend|fprd.tfvars|spoke'
      'fdev-workload|aws/environments/fdev/workload|workload.s3.tfbackend|fdev.tfvars|cluster'
      'fstg-workload|aws/environments/fstg/workload|workload.s3.tfbackend|fstg.tfvars|cluster'
      'fprd-workload|aws/environments/fprd/workload|workload.s3.tfbackend|fprd.tfvars|cluster'
      'fdev-security-irsa|aws/environments/fdev/security-irsa|security-irsa.s3.tfbackend|fdev.tfvars|identity'
      'fstg-security-irsa|aws/environments/fstg/security-irsa|security-irsa.s3.tfbackend|fstg.tfvars|identity'
      'fprd-security-irsa|aws/environments/fprd/security-irsa|security-irsa.s3.tfbackend|fprd.tfvars|identity'
    )
  fi

  if [[ "$direction" == "up" ]]; then
    printf '%s\n' "${records[@]}"
  else
    for ((index = ${#records[@]} - 1; index >= 0; index--)); do
      printf '%s\n' "${records[index]}"
    done
  fi
}

# The single AWS account the repository declares (MTS-IAC-103).
declared_account() {
  local account
  require_file "$ACCOUNT_FILE"
  account="$(sed -n 's/^AWS_ACCOUNT_ID=\([0-9]*\)[[:space:]]*$/\1/p' "$ACCOUNT_FILE" | tail -n 1)"
  [[ "$account" =~ ^[0-9]{12}$ ]] || fail "config/aws-account.env declares no 12-digit AWS_ACCOUNT_ID."
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

# The cluster names of a profile come from the literal client, project, and
# environment inputs of each cluster root's variables file, matching
# local.cluster_name ("${var.client}-${var.project}-${var.environment}-eks-main").
# Missing inputs are a hard failure: the wrapper never invents defaults.
profile_clusters() {
  local profile=$1
  local name relative_root backend_name variables_name kind variables_file
  local client project env
  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    [[ "$kind" == "cluster" ]] || continue
    variables_file="$ROOT_DIR/$relative_root/$variables_name"
    require_file "$variables_file"
    client="$(read_literal_string "$variables_file" client)"
    project="$(read_literal_string "$variables_file" project)"
    env="$(read_literal_string "$variables_file" environment)"
    [[ -n "$client" ]] || fail "No literal client in $relative_root/$variables_name."
    [[ -n "$project" ]] || fail "No literal project in $relative_root/$variables_name."
    [[ -n "$env" ]] || fail "No literal environment in $relative_root/$variables_name."
    printf '%s-%s-%s-eks-main\n' "$client" "$project" "$env"
  done < <(profile_records "$profile" down)
}

# Explicit type allow-list for the post-destroy runtime sweep (spec 003 T016).
# Only controller runtime resources are reachable: ALB/NLB load balancers plus
# their listeners and target groups, controller security groups, snapshotted
# PVC EBS volumes, and orphaned ENIs. Every protected family (ACM, Route 53,
# ECR, Secrets Manager, KMS, Terraform state S3, GitHub OIDC) falls through to
# the refusal, unreachable regardless of tags. Prints the kind or fails.
sweep_target_type() {
  case "$1" in
    arn:aws:elasticloadbalancing:*:loadbalancer/app/*|arn:aws:elasticloadbalancing:*:loadbalancer/net/*)
      printf 'load-balancer' ;;
    arn:aws:elasticloadbalancing:*:listener/*) printf 'listener' ;;
    arn:aws:elasticloadbalancing:*:targetgroup/*) printf 'target-group' ;;
    sg-*) printf 'security-group' ;;
    eni-*) printf 'network-interface' ;;
    vol-*) printf 'volume' ;;
    *) return 1 ;;
  esac
}

# Exact cluster ownership over a JSON array of {Key,Value} tags. True only for
# elbv2.k8s.aws/cluster equal to the cluster, or kubernetes.io/cluster/<name>
# owned by it. Malformed input fails closed through jq. No substring matching.
owns_cluster_tag() {
  local tags_json=$1 cluster=$2
  jq -e --arg cluster "$cluster" '
    ([.[]? | select(.Key == "elbv2.k8s.aws/cluster" and .Value == $cluster)]
     + [.[]? | select(.Key == ("kubernetes.io/cluster/" + $cluster)
                      and (.Value == "owned" or .Value == "true"))]
     | length > 0)' <<<"$tags_json" >/dev/null
}

# Exact live ownership for a PVC EBS volume: the EBS CSI cluster tag naming
# this cluster, or the Kubernetes owned cluster tag. A generic CSI true value
# names no cluster and is unsafe in this shared account.
owns_volume_tag() {
  local tags_json=$1 cluster=$2
  jq -e --arg cluster "$cluster" '
    ([.[]? | select(.Key == "ebs.csi.aws.com/cluster"
                    and .Value == $cluster)]
     + [.[]? | select(.Key == ("kubernetes.io/cluster/" + $cluster)
                      and (.Value == "owned" or .Value == "true"))]
     | length > 0)' <<<"$tags_json" >/dev/null
}

# AWS Load Balancer Controller ownership is deliberately narrower than generic
# Kubernetes cluster ownership. This prevents EKS/Terraform security groups
# carrying kubernetes.io/cluster/<name> from becoming sweep targets.
owns_controller_tag() {
  local tags_json=$1 cluster=$2
  jq -e --arg cluster "$cluster" '
    ([.[]? | select(.Key == "elbv2.k8s.aws/cluster" and .Value == $cluster)]
     | length > 0)' <<<"$tags_json" >/dev/null
}

# Fails closed unless the input parses as a JSON array of tags. A non-match
# against valid tags excludes the resource; unparseable output aborts.
require_tags_array() {
  local tags_json=$1 what=$2
  jq -e 'type == "array"' <<<"$tags_json" >/dev/null || \
    fail "Cannot parse tags of $what; failing closed."
}

# Destructive sweep calls tolerate only verified not-found or already-absent
# states (exit 0 with a log line). Permission, dependency, and every other
# error propagates to the caller. Never blanket `|| true`.
sweep_aws() {
  local output status=0
  output="$(aws "$@" 2>&1)" || status=$?
  if [[ "$status" -eq 0 ]]; then
    [[ -n "$output" ]] && printf '%s\n' "$output"
    return 0
  fi
  case "$output" in
    *NotFound*)
      printf 'SWEEP already absent: aws %s\n' "$*"
      return 0 ;;
  esac
  printf '%s\n' "$output" >&2
  return "$status"
}

# Describe calls fail closed. Only an API response that identifies a missing
# resource is absence; denied, throttled, malformed, and dependency errors are
# propagated to the caller instead of being mistaken for an empty result.
describe_for_sweep() {
  local output status=0
  output="$(aws "$@" 2>&1)" || status=$?
  if [[ "$status" -eq 0 ]]; then
    printf '%s\n' "$output"
    return 0
  fi
  case "$output" in
    *NotFound*) return 2 ;;
  esac
  printf '%s\n' "$output" >&2
  return 1
}

verify_quiescence_receipt() {
  local profile=$1
  local supplied_receipt=$2
  local supplied_volume_record=$3
  local receipt stored_profile stored_account region created_epoch stored_record
  local stored_clusters live_clusters
  local canonical_volume_record record_epoch

  [[ -n "$supplied_receipt" && -d "$supplied_receipt" ]] || \
    fail "Quiescence receipt does not exist: ${supplied_receipt:-none}. Run quiescence-receipt before planning down."
  receipt="$(cd "$supplied_receipt" && pwd -P)"
  require_file "$receipt/receipt.json"
  require_file "$receipt/checksums.sha256"
  (cd "$receipt" && sha256sum -c --quiet checksums.sha256) || fail "Quiescence receipt $receipt fails its checksum."

  stored_profile="$(jq -r '.profile // empty' "$receipt/receipt.json")"
  stored_account="$(jq -r '.account // empty' "$receipt/receipt.json")"
  region="$(jq -r '.region // empty' "$receipt/receipt.json")"
  created_epoch="$(jq -r '.created_epoch // empty' "$receipt/receipt.json")"
  stored_record="$(jq -r '.volume_record // empty' "$receipt/receipt.json")"
  stored_clusters="$(jq -c '.clusters // empty | sort' "$receipt/receipt.json")"

  [[ "$stored_profile" == "$profile" ]] || fail "Quiescence receipt profile is $stored_profile, not $profile."
  [[ "$stored_account" == "$(caller_account)" ]] || fail "Quiescence receipt account $stored_account is not the active AWS account."
  [[ "$region" == "$(profile_region "$profile")" ]] || fail "Quiescence receipt region $region is not the $profile region."
  [[ "$created_epoch" =~ ^[0-9]+$ ]] || fail "Quiescence receipt $receipt has invalid created_epoch."
  jq -e '.format == 1 and (.clusters | type == "array") and (.inventory | type == "object")' \
    "$receipt/receipt.json" >/dev/null || fail "Quiescence receipt $receipt is not a format-1 sweep receipt."

  live_clusters="$(profile_clusters "$profile" | sort | jq -R . | jq -s -c .)" || return 1
  [[ "$stored_clusters" == "$live_clusters" ]] || \
    fail "Quiescence receipt clusters $stored_clusters do not match the $profile clusters $live_clusters."

  [[ -n "$supplied_volume_record" && -d "$supplied_volume_record" ]] || \
    fail "Volume record does not exist: ${supplied_volume_record:-none}. Run snapshot-volumes before planning down."
  canonical_volume_record="$(cd "$supplied_volume_record" && pwd -P)"
  [[ "$stored_record" == "$canonical_volume_record" ]] || \
    fail "Quiescence receipt was created with a different volume record ($stored_record) than supplied ($canonical_volume_record). Create the receipt again with this record."
  record_epoch="$(record_value "$canonical_volume_record" created_epoch)"
  [[ "$record_epoch" =~ ^[0-9]+$ && "$record_epoch" -lt "$created_epoch" ]] || \
    fail "Volume record $canonical_volume_record must predate quiescence receipt $receipt. Snapshot the volumes before creating the receipt."

  printf '%s\n' "$receipt"
}

# The active session, config/aws-account.env, and every root's aws_account_id
# must name the same account before Terraform reads any state.
verify_profile() {
  local profile=$1
  local direction=${2:-up}
  local active_account declared root_account
  local name relative_root backend_name variables_name kind root backend_file variables_file

  verify_toolchain
  declared="$(declared_account)"
  active_account="$(caller_account)"
  [[ "$active_account" =~ ^[0-9]{12}$ ]] || fail "AWS STS did not return a valid account id. Renew the AWS login and retry."
  [[ "$active_account" == "$declared" ]] || \
    fail "config/aws-account.env declares AWS account $declared but the active session is $active_account."

  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    root="$ROOT_DIR/$relative_root"
    backend_file="$root/$backend_name"
    variables_file="$root/$variables_name"
    [[ -d "$root" ]] || fail "The $name root $relative_root is not in this checkout."
    require_file "$backend_file"
    require_file "$variables_file"
    root_account="$(read_literal_string "$variables_file" aws_account_id)"
    [[ "$root_account" == "$declared" ]] || \
      fail "$relative_root/$variables_name sets aws_account_id to ${root_account:-nothing}, not the account config/aws-account.env declares."

    printf 'READY  %-18s account=%s root=%s\n' "$name" "$root_account" "$relative_root"
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

# A networking root or a spoke goes down by losing its egress only; its VPC,
# subnets, and route tables hold the environment's security groups.
assert_only_egress_deletes() {
  local plan_json=$1
  local deleted
  require_file "$EGRESS_DELETE_FILTER"
  deleted="$(jq -r -f "$EGRESS_DELETE_FILTER" "$plan_json")"
  [[ -z "$deleted" ]] || fail "Saved networking plan deletes more than its egress: ${deleted//$'\n'/, }."
}

assert_no_deletes() {
  local plan_json=$1
  local deleted
  deleted="$(jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | .address' "$plan_json")"
  [[ -z "$deleted" ]] || fail "Saved unprotect plan deletes resources: ${deleted//$'\n'/, }."
}

# Prints the cluster a cluster root's state holds: absent, protected, or unprotected.
cluster_state() {
  local root=$1
  local backend_file=$2
  init_root "$root" "$backend_file" >/dev/null
  terraform -chdir="$root" show -json | jq -r '
    [.. | objects | select(.mode? == "managed" and .type? == "aws_eks_cluster")]
    | if length == 0 then "absent"
      elif any(.[]; .values.deletion_protection == true) then "protected"
      else "unprotected" end'
}

# Succeeds when a root's state lists an address matching the pattern.
state_holds() {
  local root=$1
  local backend_file=$2
  local pattern=$3
  local state
  init_root "$root" "$backend_file" >/dev/null
  state="$(terraform -chdir="$root" state list 2>/dev/null || true)"
  grep -Eq "$pattern" <<<"$state"
}

# Capacity limit L1 (decision D2 as amended on 2026-09-13). The Region's VPC quota
# holds both profiles with nothing to spare, so an up transition refuses to start
# while the VPCs that exist plus the ones it would create exceed the quota: a
# leftover default VPC would otherwise fail the last spoke after the hub and the
# first spokes already exist. A transition that creates no VPC reads nothing.
assert_vpc_capacity() {
  local profile=$1
  local region existing quota missing=0
  local name relative_root backend_name variables_name kind root

  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    case "$kind" in
      networking | hub | spoke) ;;
      *) continue ;;
    esac
    root="$ROOT_DIR/$relative_root"
    state_holds "$root" "$root/$backend_name" '\.aws_vpc\.this$' || missing=$((missing + 1))
  done < <(profile_records "$profile" up)
  ((missing > 0)) || return 0

  region="$(profile_region "$profile")"
  existing="$(aws ec2 describe-vpcs --region "$region" --query 'length(Vpcs)' --output text)"
  quota="$(aws service-quotas get-service-quota --region "$region" --service-code vpc \
    --quota-code L-F678F1CE --query 'Quota.Value' --output text)"
  quota="${quota%%.*}"
  [[ "$existing" =~ ^[0-9]+$ && "$quota" =~ ^[0-9]+$ ]] || \
    fail "Could not read the VPC count or the VPCs-per-Region quota in $region."
  ((existing + missing <= quota)) || \
    fail "$region holds $existing VPCs and this $profile up transition creates $missing more, beyond the VPCs-per-Region quota of $quota. Delete the default VPC, or any other VPC outside the platform, first (capacity limit L1)."
  printf 'VPCS   %s in %s, %s to create, quota %s\n' "$existing" "$region" "$missing" "$quota"
}

contains_value() {
  local needle=$1
  shift
  local value
  for value in "$@"; do
    [[ "$value" == "$needle" ]] && return 0
  done
  return 1
}

# Every root of a profile names one literal aws_region; the EC2 calls that find
# and snapshot persistent volumes use it.
profile_region() {
  local profile=$1
  local region="" root_region
  local name relative_root backend_name variables_name kind
  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    root_region="$(read_literal_string "$ROOT_DIR/$relative_root/$variables_name" aws_region)"
    [[ "$root_region" =~ ^[a-z]{2}(-[a-z]+)+-[0-9]+$ ]] || \
      fail "No literal aws_region was found in $relative_root/$variables_name."
    if [[ -n "$region" && "$region" != "$root_region" ]]; then
      fail "$profile mixes AWS regions $region and $root_region."
    fi
    region="$root_region"
  done < <(profile_records "$profile" down)
  printf '%s\n' "$region"
}

# The EBS CSI driver creates every dynamically provisioned volume with the
# ebs.csi.aws.com/cluster or CSIVolumeName tag (AmazonEBSCSIDriverPolicy), so
# persistent volumes are found through the EC2 API, never the Kubernetes API.
# Each line is the volume ID, its size in GiB, and its PersistentVolume name.
list_csi_volumes() {
  local region=$1
  # shellcheck disable=SC2016 # The backticks are a JMESPath literal, not a shell expansion.
  aws ec2 describe-volumes \
    --region "$region" \
    --filters 'Name=tag-key,Values=ebs.csi.aws.com/cluster,CSIVolumeName' \
    --query 'Volumes[].[VolumeId,Size,Tags[?Key==`kubernetes.io/created-for/pv/name`]|[0].Value]' \
    --output text
}

record_value() {
  local record=$1
  local key=$2
  awk -F '\t' -v key="$key" '$1 == key { print $2; exit }' "$record/record.tsv"
}

# GitOps quiescence prunes PersistentVolumeClaims, and the Delete reclaim policy
# then lets the driver delete their volumes before any Terraform plan runs (the
# 2026-09-11 teardown lost four that way). This runs while the workloads still
# do: it snapshots every volume not explicitly consented away, waits for the
# snapshots, and records the disposition of each volume.
snapshot_volumes() {
  local profile=$1
  shift
  local -a consent=("$@")
  local region active_account line volume size pv name_tag snapshot attempt timestamp record
  local -a volumes=() volume_ids=() rows=() snapshots=()

  verify_profile "$profile" down
  region="$(profile_region "$profile")"
  active_account="$(caller_account)"
  mapfile -t volumes < <(list_csi_volumes "$region" | awk 'NF')
  for line in "${volumes[@]}"; do
    volume_ids+=("${line%%$'\t'*}")
  done

  for volume in "${consent[@]}"; do
    contains_value "$volume" "${volume_ids[@]}" || \
      fail "Consent names $volume, which is not an EBS CSI volume in $region."
  done

  for line in "${volumes[@]}"; do
    IFS=$'\t' read -r volume size pv <<<"$line"
    if contains_value "$volume" "${consent[@]}"; then
      rows+=("$(printf 'volume\t%s\t%s\t%s\tconsent\t-' "$volume" "$pv" "$size")")
      printf 'CONSENT   %s (%s, %s GiB) is recorded without a snapshot.\n' "$volume" "$pv" "$size"
      continue
    fi
    name_tag=$pv
    [[ "$name_tag" != None ]] || name_tag=$volume
    snapshot="$(aws ec2 create-snapshot \
      --region "$region" \
      --volume-id "$volume" \
      --description "Lifecycle snapshot of $name_tag before the $profile profile goes down" \
      --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=$name_tag},{Key=ManagedBy,Value=aws-profile-lifecycle},{Key=LifecycleProfile,Value=$profile},{Key=SourceVolume,Value=$volume}]" \
      --query SnapshotId \
      --output text)"
    [[ "$snapshot" =~ ^snap-[0-9a-f]+$ ]] || fail "Creating a snapshot of $volume returned '$snapshot'."
    snapshots+=("$snapshot")
    rows+=("$(printf 'volume\t%s\t%s\t%s\tsnapshot\t%s' "$volume" "$pv" "$size" "$snapshot")")
    printf 'SNAPSHOT  %s (%s, %s GiB) -> %s\n' "$volume" "$pv" "$size" "$snapshot"
  done

  # Each waiter polls for ten minutes; twelve rounds allow two hours.
  if [[ ${#snapshots[@]} -gt 0 ]]; then
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
      if aws ec2 wait snapshot-completed --region "$region" --snapshot-ids "${snapshots[@]}"; then
        break
      fi
      [[ "$attempt" -lt 12 ]] || fail "The snapshots did not complete: ${snapshots[*]}."
    done
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  record="$PLAN_ROOT/volumes-${profile}-${timestamp}"
  mkdir -p "$record"
  chmod 700 "$PLAN_ROOT" "$record"
  umask 077
  {
    printf 'format\t1\n'
    printf 'profile\t%s\n' "$profile"
    printf 'account\t%s\n' "$active_account"
    printf 'region\t%s\n' "$region"
    printf 'created_epoch\t%s\n' "$(date -u +%s)"
    if [[ ${#rows[@]} -gt 0 ]]; then
      printf '%s\n' "${rows[@]}"
    fi
  } >"$record/record.tsv"
  (cd "$record" && sha256sum record.tsv >checksums.sha256)
  printf 'Volume record: %s\n' "$record"
  printf 'Create the quiescence receipt next; plan-down rejects a volume record newer than that receipt.\n'
}

# Prints the canonical record directory when the record is fit for a down plan.
verify_volume_record() {
  local profile=$1
  local supplied_record=$2
  local record region stored_profile stored_account created_epoch
  local volume size pv snapshot states
  local -a snapshots=()

  [[ -n "$supplied_record" && -d "$supplied_record" ]] || \
    fail "Volume record does not exist: ${supplied_record:-none}. Run snapshot-volumes before creating a quiescence receipt or planning down."
  record="$(cd "$supplied_record" && pwd -P)"
  require_file "$record/record.tsv"
  require_file "$record/checksums.sha256"
  (cd "$record" && sha256sum -c --quiet checksums.sha256) || fail "Volume record $record fails its checksum."

  stored_profile="$(record_value "$record" profile)"
  stored_account="$(record_value "$record" account)"
  region="$(record_value "$record" region)"
  created_epoch="$(record_value "$record" created_epoch)"
  [[ "$created_epoch" =~ ^[0-9]+$ ]] || fail "Volume record $record has invalid created_epoch."
  [[ "$stored_profile" == "$profile" ]] || fail "Volume record profile is $stored_profile, not $profile."
  [[ "$stored_account" == "$(caller_account)" ]] || fail "Volume record account $stored_account is not the active AWS account."
  [[ "$region" == "$(profile_region "$profile")" ]] || fail "Volume record region $region is not the $profile region."

  while IFS=$'\t' read -r volume size pv; do
    [[ -n "$volume" ]] || continue
    awk -F '\t' -v id="$volume" '$1 == "volume" && $2 == id { found = 1 } END { exit !found }' "$record/record.tsv" || \
      fail "EBS CSI volume $volume ($pv, $size GiB) is not in volume record $record. Snapshot it or record consent before planning down."
  done < <(list_csi_volumes "$region")

  mapfile -t snapshots < <(awk -F '\t' '$1 == "volume" && $5 == "snapshot" { print $6 }' "$record/record.tsv")
  if [[ ${#snapshots[@]} -gt 0 ]]; then
    states="$(aws ec2 describe-snapshots \
      --region "$region" \
      --snapshot-ids "${snapshots[@]}" \
      --query 'Snapshots[].[SnapshotId,State]' \
      --output text)"
    for snapshot in "${snapshots[@]}"; do
      grep -Eq "^${snapshot}[[:space:]]+completed$" <<<"$states" || fail "Recorded snapshot $snapshot is not completed."
    done
  fi
  printf '%s\n' "$record"
}

to_json_array() {
  if [[ $# -eq 0 ]]; then
    printf '[]'
  else
    printf '%s\n' "$@" | awk 'NF' | jq -R . | jq -s .
  fi
}

# Revalidates one sweep target immediately before deletion: exact resource type
# through the allow-list, live existence through a structured describe, and
# exact current cluster ownership tags. Receipt IDs alone are insufficient.
# Returns 0 when present and exactly owned (delete may proceed), 2 when already
# absent (caller skips with a log line), and 1 when the target must be refused.
# Prints the tags array for one ELBv2 ARN (load balancer, listener, or target
# group). Returns 2 when the resource is absent, 1 when tags cannot be read
# or parsed, so callers fail closed on malformed output.
elbv2_tags_for() {
  local arn=$1 region=$2
  local described count tags status=0
  described="$(describe_for_sweep elbv2 describe-tags --region "$region" \
    --resource-arns "$arn" --output json)" || status=$?
  [[ "$status" -eq 0 ]] || return "$status"
  count="$(jq -r '.TagDescriptions | length' <<<"$described" 2>/dev/null)" || return 1
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  [[ "$count" -gt 0 ]] || return 2
  tags="$(jq -c '.TagDescriptions[0].Tags // []' <<<"$described" 2>/dev/null)" || return 1
  jq -e 'type == "array"' <<<"$tags" >/dev/null 2>&1 || return 1
  printf '%s\n' "$tags"
}

revalidate_sweep_target() {
  local kind=$1 id=$2 cluster=$3 region=$4 snapshot=${5:-}
  local classified described selected tags_json state entry_type tag_status
  local found

  classified="$(sweep_target_type "$id")" || {
    printf 'ERROR: Sweep target %s is not an allow-listed runtime type; refusing.\n' "$id" >&2
    return 1
  }
  [[ "$classified" == "$kind" ]] || {
    printf 'ERROR: Sweep target %s is a %s, not a %s; refusing.\n' "$id" "$classified" "$kind" >&2
    return 1
  }

  case "$kind" in
    load-balancer)
      described="$(describe_for_sweep elbv2 describe-load-balancers --region "$region" \
        --load-balancer-arns "$id" --output json)" || {
        tag_status=$?; return "$tag_status"; }
      jq -e . <<<"$described" >/dev/null 2>&1 || return 1
      entry_type="$(jq -r --arg id "$id" '.LoadBalancers[]? | select(.LoadBalancerArn == $id) | .Type // empty' <<<"$described")" || return 1
      [[ -n "$entry_type" ]] || return 2
      [[ "$entry_type" == "application" || "$entry_type" == "network" ]] || {
        printf 'ERROR: Load balancer %s has unexpected type %s; refusing.\n' "$id" "$entry_type" >&2
        return 1
      }
      tags_json="$(elbv2_tags_for "$id" "$region")" || {
        tag_status=$?
        [[ "$tag_status" -eq 2 ]] && return 2
        printf 'ERROR: Cannot read tags of load balancer %s; refusing.\n' "$id" >&2
        return 1
      }
      owns_controller_tag "$tags_json" "$cluster" || {
        printf 'ERROR: Load balancer %s is not owned by cluster %s; refusing.\n' "$id" "$cluster" >&2
        return 1
      }
      ;;
    listener)
      described="$(describe_for_sweep elbv2 describe-listeners --region "$region" \
        --listener-arns "$id" --output json)" || {
        tag_status=$?; return "$tag_status"; }
      jq -e . <<<"$described" >/dev/null 2>&1 || return 1
      found="$(jq -r --arg id "$id" '[.Listeners[]? | .ListenerArn] | map(select(. == $id)) | length' <<<"$described")" || return 1
      [[ "$found" =~ ^[0-9]+$ && "$found" -gt 0 ]] || return 2
      tags_json="$(elbv2_tags_for "$id" "$region")" || {
        tag_status=$?
        [[ "$tag_status" -eq 2 ]] && return 2
        printf 'ERROR: Cannot read tags of listener %s; refusing.\n' "$id" >&2
        return 1
      }
      owns_controller_tag "$tags_json" "$cluster" || {
        printf 'ERROR: Listener %s is not owned by cluster %s; refusing.\n' "$id" "$cluster" >&2
        return 1
      }
      ;;
    target-group)
      described="$(describe_for_sweep elbv2 describe-target-groups --region "$region" \
        --target-group-arns "$id" --output json)" || {
        tag_status=$?; return "$tag_status"; }
      jq -e . <<<"$described" >/dev/null 2>&1 || return 1
      found="$(jq -r --arg id "$id" '[.TargetGroups[]? | .TargetGroupArn] | map(select(. == $id)) | length' <<<"$described")" || return 1
      [[ "$found" =~ ^[0-9]+$ && "$found" -gt 0 ]] || return 2
      tags_json="$(elbv2_tags_for "$id" "$region")" || {
        tag_status=$?
        [[ "$tag_status" -eq 2 ]] && return 2
        printf 'ERROR: Cannot read tags of target group %s; refusing.\n' "$id" >&2
        return 1
      }
      owns_controller_tag "$tags_json" "$cluster" || {
        printf 'ERROR: Target group %s is not owned by cluster %s; refusing.\n' "$id" "$cluster" >&2
        return 1
      }
      ;;
    security-group)
      described="$(describe_for_sweep ec2 describe-security-groups --region "$region" \
        --group-ids "$id" --output json)" || {
        tag_status=$?; return "$tag_status"; }
      jq -e . <<<"$described" >/dev/null 2>&1 || return 1
      selected="$(jq -c --arg id "$id" '[.SecurityGroups[]? | select(.GroupId == $id)] | .[0] // empty' <<<"$described")" || return 1
      [[ -n "$selected" ]] || return 2
      tags_json="$(jq -c '.Tags // []' <<<"$selected")" || return 1
      jq -e 'type == "array"' <<<"$tags_json" >/dev/null 2>&1 || return 1
      owns_controller_tag "$tags_json" "$cluster" || {
        printf 'ERROR: Security group %s is not owned by cluster %s; refusing.\n' "$id" "$cluster" >&2
        return 1
      }
      ;;
    network-interface)
      described="$(describe_for_sweep ec2 describe-network-interfaces --region "$region" \
        --network-interface-ids "$id" --output json)" || {
        tag_status=$?; return "$tag_status"; }
      jq -e . <<<"$described" >/dev/null 2>&1 || return 1
      selected="$(jq -c --arg id "$id" '[.NetworkInterfaces[]? | select(.NetworkInterfaceId == $id)] | .[0] // empty' <<<"$described")" || return 1
      [[ -n "$selected" ]] || return 2
      state="$(jq -r '.Status // empty' <<<"$selected")" || return 1
      [[ "$state" == "available" ]] || {
        printf 'ERROR: Network interface %s remains %s, not available; refusing.\n' "$id" "$state" >&2
        return 1
      }
      tags_json="$(jq -c '.TagSet // []' <<<"$selected")" || return 1
      jq -e 'type == "array"' <<<"$tags_json" >/dev/null 2>&1 || return 1
      owns_controller_tag "$tags_json" "$cluster" || {
        printf 'ERROR: Network interface %s is not owned by cluster %s; refusing.\n' "$id" "$cluster" >&2
        return 1
      }
      ;;
    volume)
      [[ -n "$snapshot" ]] || {
        printf 'ERROR: Volume %s has no recorded snapshot; refusing.\n' "$id" >&2
        return 1
      }
      described="$(describe_for_sweep ec2 describe-volumes --region "$region" \
        --volume-ids "$id" --output json)" || {
        tag_status=$?; return "$tag_status"; }
      jq -e . <<<"$described" >/dev/null 2>&1 || return 1
      selected="$(jq -c --arg id "$id" '[.Volumes[]? | select(.VolumeId == $id)] | .[0] // empty' <<<"$described")" || return 1
      [[ -n "$selected" ]] || return 2
      state="$(jq -r '.State // empty' <<<"$selected")" || return 1
      [[ "$state" == "available" ]] || {
        printf 'ERROR: Volume %s has state %s, not available; refusing.\n' "$id" "$state" >&2
        return 1
      }
      tags_json="$(jq -c '.Tags // []' <<<"$selected")" || return 1
      jq -e 'type == "array"' <<<"$tags_json" >/dev/null 2>&1 || return 1
      owns_volume_tag "$tags_json" "$cluster" || {
        printf 'ERROR: Volume %s is not owned by cluster %s; refusing.\n' "$id" "$cluster" >&2
        return 1
      }
      state="$(describe_for_sweep ec2 describe-snapshots --region "$region" --snapshot-ids "$snapshot" \
        --query 'Snapshots[0].State' --output text)" || {
        printf 'ERROR: Cannot read recorded snapshot %s for volume %s; refusing.\n' "$snapshot" "$id" >&2
        return 1
      }
      [[ "$state" == "completed" ]] || {
        printf 'ERROR: Recorded snapshot %s for volume %s is %s, not completed; refusing.\n' "$snapshot" "$id" "$state" >&2
        return 1
      }
      ;;
    *)
      printf 'ERROR: Unknown sweep kind %s for %s; refusing.\n' "$kind" "$id" >&2
      return 1 ;;
  esac
  return 0
}

# Quiescence receipt (spec 003 T016): checksummed JSON evidence that replaces
# the former GitOps revision gate. Inventories every sweepable runtime resource whose live,
# exact cluster ownership tags name a profile cluster, and records the volume
# record it was created with. Volume-record-before-receipt ordering is enforced
# by creation time: the receipt is truthfully stamped now, and creation refuses
# when the clock has not advanced past the volume record.
quiescence_receipt() {
  local profile=$1
  local supplied_volume_record=$2
  local region active_account timestamp receipt_dir
  local canonical_volume_record record_epoch now_epoch waited created_epoch
  local clusters_text cluster_list_json lbs_json lb_tags owned_cluster
  local listeners_json listener_tags tgs_json tg_tags sgs_json
  local sg_tags_json vol_json vol_selected vol_status vol_tags
  local enis_json eni_tags_json
  local lb_arn lb_type listener_arn tg_arn sg_id eni_id
  local lb_row sg_row eni_row
  local marker vol_id pv size status snap_id
  local -a clusters=()
  local -a load_balancers=()
  local -a listeners=()
  local -a target_groups=()
  local -a security_groups=()
  local -a volumes=()
  local -a network_interfaces=()

  verify_toolchain
  verify_profile "$profile" down
  region="$(profile_region "$profile")"
  active_account="$(caller_account)"
  canonical_volume_record="$(verify_volume_record "$profile" "$supplied_volume_record")"
  record_epoch="$(record_value "$canonical_volume_record" created_epoch)"

  clusters_text="$(profile_clusters "$profile")" || return 1
  mapfile -t clusters <<<"$clusters_text"
  [[ ${#clusters[@]} -gt 0 && -n "${clusters[0]}" ]] || fail "No cluster found for profile $profile."

  cluster_list_json="$(printf '%s\n' "${clusters[@]}" | jq -R . | jq -s .)"

  # 1. Cluster-owned ALB/NLB load balancers, each with its own exact tag, plus
  # each listener behind its own exact listener tag (never inherited trust).
  # Structured JSON throughout; unparseable output fails closed.
  lbs_json="$(aws elbv2 describe-load-balancers --region "$region" --output json)" || \
    fail "Cannot list load balancers in $region."
  jq -e . <<<"$lbs_json" >/dev/null 2>&1 || fail "Cannot parse load balancers in $region; failing closed."
  while IFS= read -r lb_row; do
    lb_arn="$(jq -r '.arn // empty' <<<"$lb_row")" || fail "Cannot parse load balancer entry; failing closed."
    lb_type="$(jq -r '.type // empty' <<<"$lb_row")" || fail "Cannot parse load balancer entry; failing closed."
    [[ -n "$lb_arn" ]] || continue
    [[ "$lb_type" == "application" || "$lb_type" == "network" ]] || continue
    sweep_target_type "$lb_arn" >/dev/null || continue
    lb_tags="$(elbv2_tags_for "$lb_arn" "$region")" || \
      fail "Cannot read tags of load balancer $lb_arn; failing closed."
    owned_cluster=""
    for c in "${clusters[@]}"; do
      if owns_controller_tag "$lb_tags" "$c"; then owned_cluster="$c"; break; fi
    done
    [[ -n "$owned_cluster" ]] || continue
    load_balancers+=("$lb_arn")
    listeners_json="$(aws elbv2 describe-listeners --region "$region" \
      --load-balancer-arn "$lb_arn" --output json)" || \
      fail "Cannot list listeners of load balancer $lb_arn; failing closed."
    jq -e . <<<"$listeners_json" >/dev/null 2>&1 || \
      fail "Cannot parse listeners of load balancer $lb_arn; failing closed."
    while IFS= read -r listener_arn; do
      [[ -n "$listener_arn" ]] || continue
      sweep_target_type "$listener_arn" >/dev/null || continue
      listener_tags="$(elbv2_tags_for "$listener_arn" "$region")" || \
        fail "Cannot read tags of listener $listener_arn; failing closed."
      owns_controller_tag "$listener_tags" "$owned_cluster" || continue
      listeners+=("$listener_arn")
    done < <(jq -r '.Listeners[]? | .ListenerArn // empty' <<<"$listeners_json")
  done < <(jq -c '.LoadBalancers[]? | {arn: .LoadBalancerArn, type: .Type}' <<<"$lbs_json")

  # 2. Cluster-owned target groups behind their own exact tags.
  tgs_json="$(aws elbv2 describe-target-groups --region "$region" --output json)" || \
    fail "Cannot list target groups in $region."
  jq -e . <<<"$tgs_json" >/dev/null 2>&1 || fail "Cannot parse target groups in $region; failing closed."
  while IFS= read -r tg_arn; do
    [[ -n "$tg_arn" ]] || continue
    sweep_target_type "$tg_arn" >/dev/null || continue
    tg_tags="$(elbv2_tags_for "$tg_arn" "$region")" || \
      fail "Cannot read tags of target group $tg_arn; failing closed."
    for c in "${clusters[@]}"; do
      if owns_controller_tag "$tg_tags" "$c"; then target_groups+=("$tg_arn"); break; fi
    done
  done < <(jq -r '.TargetGroups[]? | .TargetGroupArn // empty' <<<"$tgs_json")

  # 3. Controller security groups behind exact tags, read with explicit output.
  sgs_json="$(aws ec2 describe-security-groups --region "$region" --output json)" || \
    fail "Cannot list security groups in $region."
  jq -e . <<<"$sgs_json" >/dev/null 2>&1 || fail "Cannot parse security groups in $region; failing closed."
  while IFS= read -r sg_row; do
    sg_id="$(jq -r '.id // empty' <<<"$sg_row")" || fail "Cannot parse security group entry; failing closed."
    sg_tags_json="$(jq -c '.tags // []' <<<"$sg_row")" || fail "Cannot parse security group entry; failing closed."
    [[ -n "$sg_id" ]] || continue
    sweep_target_type "$sg_id" >/dev/null || continue
    require_tags_array "$sg_tags_json" "security group $sg_id"
    for c in "${clusters[@]}"; do
      if owns_controller_tag "$sg_tags_json" "$c"; then security_groups+=("$sg_id"); break; fi
    done
  done < <(jq -c '.SecurityGroups[]? | {id: .GroupId, tags: (.Tags // [])}' <<<"$sgs_json")

  # 4. Recorded PVC volumes: exact live cluster-scoped ownership tags plus the
  # record entry plus a live completed snapshot. Consent entries never sweep.
  while IFS=$'\t' read -r marker vol_id pv size status snap_id; do
    [[ "$marker" == "volume" && "$status" == "snapshot" && -n "$snap_id" && "$snap_id" != "-" ]] || continue
    sweep_target_type "$vol_id" >/dev/null || continue
    vol_json="$(describe_for_sweep ec2 describe-volumes --region "$region" --volume-ids "$vol_id" \
      --output json)" || {
      vol_status=$?
      [[ "$vol_status" -eq 2 ]] && continue
      fail "Cannot describe volume $vol_id; failing closed."
    }
    jq -e . <<<"$vol_json" >/dev/null 2>&1 || fail "Cannot parse volume $vol_id; failing closed."
    vol_selected="$(jq -c --arg id "$vol_id" '[.Volumes[]? | select(.VolumeId == $id)] | .[0] // empty' <<<"$vol_json")" || \
      fail "Cannot parse volume $vol_id; failing closed."
    [[ -n "$vol_selected" ]] || continue
    vol_tags="$(jq -c '.Tags // []' <<<"$vol_selected")" || fail "Cannot parse tags of volume $vol_id; failing closed."
    require_tags_array "$vol_tags" "volume $vol_id"
    for c in "${clusters[@]}"; do
      if owns_volume_tag "$vol_tags" "$c"; then volumes+=("$vol_id"); break; fi
    done
  done <"$canonical_volume_record/record.tsv"

  # 5. ENIs left by the controller: inventory their pre-destroy state and
  # require available immediately before deletion after the load balancer is gone.
  enis_json="$(aws ec2 describe-network-interfaces --region "$region" --output json)" || \
    fail "Cannot list network interfaces in $region."
  jq -e . <<<"$enis_json" >/dev/null 2>&1 || fail "Cannot parse network interfaces in $region; failing closed."
  while IFS= read -r eni_row; do
    eni_id="$(jq -r '.id // empty' <<<"$eni_row")" || fail "Cannot parse network interface entry; failing closed."
    eni_tags_json="$(jq -c '.tags // []' <<<"$eni_row")" || fail "Cannot parse network interface entry; failing closed."
    [[ -n "$eni_id" ]] || continue
    sweep_target_type "$eni_id" >/dev/null || continue
    require_tags_array "$eni_tags_json" "network interface $eni_id"
    for c in "${clusters[@]}"; do
      if owns_controller_tag "$eni_tags_json" "$c"; then network_interfaces+=("$eni_id"); break; fi
    done
  done < <(jq -c '.NetworkInterfaces[]? | {id: .NetworkInterfaceId, status: .Status, tags: (.TagSet // [])}' <<<"$enis_json")

  # Truthful evidence: the receipt is stamped with the real clock, and creation
  # refuses when the clock has not advanced past the volume record, so the
  # volume-record-before-receipt ordering is never fabricated.
  now_epoch="$(date -u +%s)"
  waited=0
  while [[ "$now_epoch" -le "$record_epoch" && "$waited" -lt 5 ]]; do
    sleep 1
    now_epoch="$(date -u +%s)"
    waited=$((waited + 1))
  done
  if [[ "$now_epoch" -le "$record_epoch" ]]; then
    fail "System clock ($now_epoch) did not advance past the volume record ($record_epoch); wait a second and retry quiescence-receipt."
  fi
  created_epoch="$now_epoch"

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  receipt_dir="$PLAN_ROOT/quiescence-${profile}-${timestamp}"
  mkdir -p "$receipt_dir"
  chmod 700 "$PLAN_ROOT" "$receipt_dir"
  umask 077

  json_clusters="$cluster_list_json"
  json_lbs="$(to_json_array ${load_balancers[@]+"${load_balancers[@]}"})"
  json_listeners="$(to_json_array ${listeners[@]+"${listeners[@]}"})"
  json_tgs="$(to_json_array ${target_groups[@]+"${target_groups[@]}"})"
  json_sgs="$(to_json_array ${security_groups[@]+"${security_groups[@]}"})"
  json_vols="$(to_json_array ${volumes[@]+"${volumes[@]}"})"
  json_enis="$(to_json_array ${network_interfaces[@]+"${network_interfaces[@]}"})"

  jq -n \
    --arg profile "$profile" \
    --arg account "$active_account" \
    --arg region "$region" \
    --arg created_epoch "$created_epoch" \
    --arg volume_record "$canonical_volume_record" \
    --argjson clusters "$json_clusters" \
    --argjson lbs "$json_lbs" \
    --argjson listeners "$json_listeners" \
    --argjson tgs "$json_tgs" \
    --argjson sgs "$json_sgs" \
    --argjson vols "$json_vols" \
    --argjson enis "$json_enis" \
    '{
      format: 1,
      profile: $profile,
      account: $account,
      region: $region,
      created_epoch: ($created_epoch | tonumber),
      volume_record: $volume_record,
      clusters: $clusters,
      inventory: {
        load_balancers: $lbs,
        listeners: $listeners,
        target_groups: $tgs,
        security_groups: $sgs,
        volumes: $vols,
        network_interfaces: $enis
      }
    }' >"$receipt_dir/receipt.json"

  (cd "$receipt_dir" && sha256sum receipt.json >checksums.sha256)
  printf 'Quiescence receipt: %s\n' "$receipt_dir"
}

plan_profile() {
  local profile=$1
  local direction=$2
  local supplied_receipt=${3:-}
  local supplied_volume_record=${4:-}
  local receipt=""
  local volume_record=""
  local timestamp bundle active_account commit pass="complete"
  local any_protected=false any_absent=false has_identity=false has_hub=false hub_present=false
  local name relative_root backend_name variables_name kind root plan_file json_file
  local -a plan_args
  local -A cluster_of=()

  verify_git_clean
  verify_profile "$profile" "$direction"
  if [[ "$direction" == "up" ]]; then
    assert_vpc_capacity "$profile"
  fi
  if [[ "$direction" == "down" ]]; then
    volume_record="$(verify_volume_record "$profile" "$supplied_volume_record")"
    receipt="$(verify_quiescence_receipt "$profile" "$supplied_receipt" "$volume_record")"
  fi

  # Three transitions take a second bundle. Amazon EKS refuses to delete a
  # protected cluster, so a down transition first turns the protection off in a
  # bundle of its own. The spokes read the hub's transit gateway at plan time, so
  # an up transition without the hub creates the hub first. The IRSA pass reads
  # its cluster's issuer, so an up transition without a cluster creates the
  # cluster first.
  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    root="$ROOT_DIR/$relative_root"
    case "$kind" in
      cluster)
        cluster_of[$name]="$(cluster_state "$root" "$root/$backend_name")"
        [[ "${cluster_of[$name]}" != "protected" ]] || any_protected=true
        [[ "${cluster_of[$name]}" != "absent" ]] || any_absent=true
        ;;
      identity) has_identity=true ;;
      hub)
        has_hub=true
        if state_holds "$root" "$root/$backend_name" '\.aws_ec2_transit_gateway\.this$'; then
          hub_present=true
        fi
        ;;
    esac
  done < <(profile_records "$profile" up)
  if [[ "$direction" == "down" && "$any_protected" == true ]]; then
    pass="unprotect"
  elif [[ "$direction" == "up" && "$has_hub" == true && "$hub_present" == false ]]; then
    pass="hub-first"
  elif [[ "$direction" == "up" && "$has_identity" == true && "$any_absent" == true ]]; then
    pass="cluster-first"
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
    printf 'receipt\t%s\n' "$receipt"
    printf 'pass\t%s\n' "$pass"
    if [[ -n "$volume_record" ]]; then
      printf 'volume_record\t%s\n' "$volume_record"
    fi
  } >"$bundle/metadata.tsv"
  if [[ -n "$volume_record" ]]; then
    cp "$volume_record/record.tsv" "$bundle/volume-record.tsv"
  fi
  if [[ -n "$receipt" ]]; then
    cp "$receipt/receipt.json" "$bundle/quiescence-receipt.json"
  fi

  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    case "$pass" in
      unprotect) [[ "$kind" == "cluster" && "${cluster_of[$name]:-}" == "protected" ]] || continue ;;
      hub-first) [[ "$kind" == "hub" ]] || continue ;;
      cluster-first) [[ "$kind" != "identity" ]] || continue ;;
    esac
    root="$ROOT_DIR/$relative_root"
    plan_file="$bundle/$name.tfplan"
    json_file="$bundle/$name.json"

    printf 'Planning %s %s for %s...\n' "$profile" "$direction" "$name"
    init_root "$root" "$root/$backend_name"

    plan_args=(
      -input=false
      -lock-timeout=5m
      -var-file="$root/$variables_name"
      -out="$plan_file"
    )

    case "$kind:$direction" in
      networking:up)
        terraform -chdir="$root" plan "${plan_args[@]}" -var=nat_gateways_enabled=true
        ;;
      networking:down)
        terraform -chdir="$root" plan "${plan_args[@]}" -var=nat_gateways_enabled=false
        ;;
      spoke:up)
        terraform -chdir="$root" plan "${plan_args[@]}" -var=transit_enabled=true
        ;;
      spoke:down)
        terraform -chdir="$root" plan "${plan_args[@]}" -var=transit_enabled=false
        ;;
      cluster:down)
        if [[ "$pass" == "unprotect" ]]; then
          terraform -chdir="$root" plan "${plan_args[@]}" \
            -target=module.eks_cluster.aws_eks_cluster.this \
            -var=cluster_deletion_protection=false
        elif [[ "$profile" == "economical" ]]; then
          terraform -chdir="$root" plan -destroy "${plan_args[@]}" \
            -target=module.eks_cluster \
            -target=module.bootstrap_node_group \
            -target=aws_route53_record.ingress
        else
          terraform -chdir="$root" plan -destroy "${plan_args[@]}"
        fi
        ;;
      identity:down | hub:down)
        terraform -chdir="$root" plan -destroy "${plan_args[@]}"
        ;;
      *)
        terraform -chdir="$root" plan "${plan_args[@]}"
        ;;
    esac

    terraform -chdir="$root" show -json "$plan_file" >"$json_file"
    if [[ "$direction" == "down" ]]; then
      assert_no_durable_deletes "$json_file"
      if [[ "$kind" == "networking" || "$kind" == "spoke" ]]; then
        assert_only_egress_deletes "$json_file"
      elif [[ "$pass" == "unprotect" ]]; then
        assert_no_deletes "$json_file"
      fi
    fi
    printf 'root\t%s\t%s\t%s\n' "$name" "$relative_root" "$name.tfplan" >>"$bundle/metadata.tsv"
  done < <(profile_records "$profile" "$direction")

  (
    cd "$bundle"
    checksum_files=(./*.tfplan ./*.json metadata.tsv)
    if [[ -f volume-record.tsv ]]; then
      checksum_files+=(volume-record.tsv)
    fi
    if [[ -f quiescence-receipt.json ]]; then
      checksum_files+=(quiescence-receipt.json)
    fi
    sha256sum "${checksum_files[@]}" >checksums.sha256
  )
  printf 'Saved plan bundle: %s\n' "$bundle"
  case "$pass" in
    unprotect)
      printf 'A cluster refuses deletion, so this bundle only turns deletion protection off on each protected cluster.\n'
      printf 'Apply it, then plan down again with the same receipt and volume record for the destroy bundle.\n'
      ;;
    hub-first)
      printf 'The egress hub does not exist yet and the spokes read its transit gateway, so this bundle holds only the hub.\n'
      printf 'Apply it, then plan up again for the spokes and the clusters.\n'
      ;;
    cluster-first)
      printf 'The cluster does not exist yet and the IRSA pass reads it, so this bundle holds the network and the cluster.\n'
      printf 'Apply it, then plan up again for the IRSA pass.\n'
      ;;
  esac
  printf 'Inspect it before apply: %s inspect %s\n' "$0" "$bundle"
}

metadata_value() {
  local bundle=$1
  local key=$2
  awk -F '\t' -v key="$key" '$1 == key { print $2; exit }' "$bundle/metadata.tsv"
}

inspect_bundle() {
  local bundle
  local name relative_root plan_name
  bundle="$(canonical_bundle_path "$1")"
  require_file "$bundle/metadata.tsv"
  require_file "$bundle/checksums.sha256"
  (cd "$bundle" && sha256sum -c checksums.sha256)

  printf 'Profile: %s\n' "$(metadata_value "$bundle" profile)"
  printf 'Direction: %s\n' "$(metadata_value "$bundle" direction)"
  printf 'Pass: %s\n' "$(metadata_value "$bundle" pass)"
  printf 'Account: %s\n' "$(metadata_value "$bundle" account)"
  printf 'Commit: %s\n' "$(metadata_value "$bundle" commit)"
  printf 'Receipt: %s\n' "$(metadata_value "$bundle" receipt)"
  printf 'Volume record: %s\n' "$(metadata_value "$bundle" volume_record)"

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

# Post-destroy runtime sweep (spec 003 T016). Runs during a down apply AFTER
# every workload/cluster plan has destroyed the cluster(s) and BEFORE the first
# networking plan applies. Deletes only allow-listed controller runtime
# resources with exact current cluster ownership tags, revalidated immediately
# before each deletion. Idempotent: already-absent targets are skipped or
# tolerated, and a rerun after a partial failure completes. Every deletion and
# every root apply is logged as an EVENT line, forming one ordered event log.
execute_post_destroy_sweep() {
  local bundle=$1
  local receipt_file="$bundle/quiescence-receipt.json"
  local receipt_dir vol_record_file vol_rec_dir
  local region profile clusters_text
  local -a clusters=()
  local id snap_id
  local -a listeners=() lbs=() tgs=() sgs=() vols=() enis=()

  receipt_dir="$(metadata_value "$bundle" receipt)"
  [[ -n "$receipt_dir" && -d "$receipt_dir" ]] || \
    fail "The down bundle carries no quiescence receipt. Re-plan with --receipt."
  require_file "$receipt_file"
  require_file "$receipt_dir/receipt.json"
  require_file "$receipt_dir/checksums.sha256"
  (cd "$receipt_dir" && sha256sum -c --quiet checksums.sha256) || \
    fail "Quiescence receipt $receipt_dir fails its checksum at apply."
  cmp -s "$receipt_dir/receipt.json" "$receipt_file" || \
    fail "The bundle's quiescence receipt copy differs from $receipt_dir/receipt.json. Re-plan."

  vol_rec_dir="$(metadata_value "$bundle" volume_record)"
  vol_record_file="$bundle/volume-record.tsv"
  [[ -n "$vol_rec_dir" && -d "$vol_rec_dir" ]] || \
    fail "The down bundle carries no persistent-volume record. Re-plan with --volume-record."
  require_file "$vol_record_file"
  (cd "$vol_rec_dir" && sha256sum -c --quiet checksums.sha256) || \
    fail "Volume record $vol_rec_dir fails its checksum at apply."
  cmp -s "$vol_rec_dir/record.tsv" "$vol_record_file" || \
    fail "The bundle's volume record copy differs from $vol_rec_dir/record.tsv. Re-plan."

  profile="$(jq -r '.profile // empty' "$receipt_file")"
  region="$(jq -r '.region // empty' "$receipt_file")"
  [[ -n "$profile" && -n "$region" ]] || fail "The quiescence receipt has no profile or region."
  [[ "$(jq -r '.account // empty' "$receipt_file")" == "$(caller_account)" ]] || \
    fail "Quiescence receipt account does not match the active AWS account at apply."
  [[ "$region" == "$(profile_region "$profile")" ]] || \
    fail "Quiescence receipt region $region is not the $profile region at apply."
  clusters_text="$(profile_clusters "$profile")" || return 1
  mapfile -t clusters <<<"$clusters_text"
  [[ "$(jq -c '.clusters | sort' "$receipt_file")" == "$(printf '%s\n' "${clusters[@]}" | sort | jq -R . | jq -s -c .)" ]] || \
    fail "Quiescence receipt clusters do not match the $profile clusters at apply."

  printf 'Executing post-destroy runtime sweep for %s in %s...\n' "$profile" "$region"

  mapfile -t listeners < <(jq -r '.inventory.listeners[]? // empty' "$receipt_file")
  mapfile -t lbs < <(jq -r '.inventory.load_balancers[]? // empty' "$receipt_file")
  mapfile -t tgs < <(jq -r '.inventory.target_groups[]? // empty' "$receipt_file")
  mapfile -t sgs < <(jq -r '.inventory.security_groups[]? // empty' "$receipt_file")
  mapfile -t vols < <(jq -r '.inventory.volumes[]? // empty' "$receipt_file")
  mapfile -t enis < <(jq -r '.inventory.network_interfaces[]? // empty' "$receipt_file")

  sweep_one() {
    local kind=$1 id=$2 region=$3 snapshot=${4:-}
    shift 4
    local owner="" refused=false c st
    [[ -n "$id" ]] || return 0
    sweep_target_type "$id" >/dev/null || \
      fail "Sweep target $id is not an allow-listed runtime type; refusing."
    [[ "$(sweep_target_type "$id")" == "$kind" ]] || \
      fail "Sweep target $id is not a $kind; refusing."
    for c in "$@"; do
      st=0
      revalidate_sweep_target "$kind" "$id" "$c" "$region" "$snapshot" || st=$?
      if [[ "$st" -eq 0 ]]; then
        owner="$c"
        break
      elif [[ "$st" -eq 1 ]]; then
        refused=true
      fi
    done
    if [[ -z "$owner" ]]; then
      if [[ "$refused" == true ]]; then
        fail "Sweep target $kind $id failed revalidation; refusing."
      fi
      printf 'SWEEP skip %s %s: already absent.\n' "$kind" "$id"
      return 0
    fi
    case "$kind" in
      load-balancer) sweep_aws elbv2 delete-load-balancer --region "$region" --load-balancer-arn "$id" ;;
      listener) sweep_aws elbv2 delete-listener --region "$region" --listener-arn "$id" ;;
      target-group) sweep_aws elbv2 delete-target-group --region "$region" --target-group-arn "$id" ;;
      security-group) sweep_aws ec2 delete-security-group --region "$region" --group-id "$id" ;;
      volume) sweep_aws ec2 delete-volume --region "$region" --volume-id "$id" ;;
      network-interface) sweep_aws ec2 delete-network-interface --region "$region" --network-interface-id "$id" ;;
    esac || fail "Sweep deletion of $kind $id failed."
    printf 'EVENT sweep delete %s %s\n' "$kind" "$id"
  }

  for id in ${listeners[@]+"${listeners[@]}"}; do sweep_one listener "$id" "$region" "" "${clusters[@]}"; done
  for id in ${lbs[@]+"${lbs[@]}"}; do sweep_one load-balancer "$id" "$region" "" "${clusters[@]}"; done
  if [[ ${#lbs[@]} -gt 0 ]]; then
    for id in "${lbs[@]}"; do
      sweep_aws elbv2 wait load-balancers-deleted --region "$region" --load-balancer-arns "$id" || \
        fail "Load balancer $id did not finish deleting."
    done
  fi
  for id in ${tgs[@]+"${tgs[@]}"}; do sweep_one target-group "$id" "$region" "" "${clusters[@]}"; done
  for id in ${enis[@]+"${enis[@]}"}; do sweep_one network-interface "$id" "$region" "" "${clusters[@]}"; done
  for id in ${sgs[@]+"${sgs[@]}"}; do sweep_one security-group "$id" "$region" "" "${clusters[@]}"; done
  for id in ${vols[@]+"${vols[@]}"}; do
    snap_id="$(awk -F '\t' -v vol="$id" '$1 == "volume" && $2 == vol && $5 == "snapshot" { print $6; exit }' "$vol_record_file")"
    [[ -n "$snap_id" && "$snap_id" != "-" ]] || \
      fail "Sweep volume $id has no recorded snapshot; refusing."
    sweep_one volume "$id" "$region" "$snap_id" "${clusters[@]}"
  done

  printf 'Post-destroy runtime sweep completed successfully.\n'
}

apply_bundle() {
  local requested_profile=$1
  local requested_direction=$2
  local supplied_bundle=$3
  local bundle
  local stored_profile stored_direction stored_account stored_commit stored_pass active_account
  local name relative_root plan_name root
  local sweep_executed=false

  bundle="$(canonical_bundle_path "$supplied_bundle")"
  verify_toolchain
  verify_git_clean
  require_file "$bundle/metadata.tsv"
  require_file "$bundle/checksums.sha256"
  stored_profile="$(metadata_value "$bundle" profile)"
  stored_direction="$(metadata_value "$bundle" direction)"
  stored_account="$(metadata_value "$bundle" account)"
  stored_commit="$(metadata_value "$bundle" commit)"
  stored_pass="$(metadata_value "$bundle" pass)"
  active_account="$(caller_account)"

  [[ "$stored_profile" == "$requested_profile" ]] || fail "Bundle profile is $stored_profile, not $requested_profile."
  [[ "$stored_direction" == "$requested_direction" ]] || fail "Bundle direction is $stored_direction, not $requested_direction."
  [[ "$stored_account" == "$active_account" ]] || fail "Bundle account is $stored_account but AWS STS reports $active_account."
  [[ "$stored_commit" == "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]] || fail "The checked-out commit differs from the plan bundle commit. Re-plan."
  if [[ "$requested_direction" == "down" ]]; then
    [[ -n "$(metadata_value "$bundle" receipt)" && -f "$bundle/quiescence-receipt.json" ]] || \
      fail "The down bundle carries no quiescence receipt. Re-plan with --receipt."
    [[ -n "$(metadata_value "$bundle" volume_record)" && -f "$bundle/volume-record.tsv" ]] || \
      fail "The down bundle carries no persistent-volume record. Re-plan with --volume-record."
  fi
  (cd "$bundle" && sha256sum -c checksums.sha256)

  while IFS=$'\t' read -r marker name relative_root plan_name; do
    [[ "$marker" == "root" ]] || continue
    root="$ROOT_DIR/$relative_root"
    require_file "$bundle/$plan_name"

    # Post-destroy runtime sweep (spec 003 T016): runs during a down apply
    # after every workload/cluster plan has destroyed the cluster(s) and
    # before the first networking plan applies.
    if [[ "$requested_direction" == "down" && "$stored_pass" != "unprotect" && "$sweep_executed" == false ]]; then
      case "$name" in
        *-networking)
          execute_post_destroy_sweep "$bundle"
          sweep_executed=true
          ;;
      esac
    fi

    backup_state "$name" "$root" "$stored_account"
    printf 'EVENT apply %s\n' "$name"
    printf 'Applying reviewed saved plan for %s...\n' "$name"
    terraform -chdir="$root" apply -input=false "$bundle/$plan_name"
  done <"$bundle/metadata.tsv"
}

# A root is up when its state holds what the down transition removes: the NAT
# gateways of a networking root, a spoke's transit attachment, the hub's transit
# gateway, the cluster, or the IRSA pass's roles.
status_profile() {
  local profile=$1
  local name relative_root backend_name variables_name kind root pattern
  verify_profile "$profile" up

  while IFS='|' read -r name relative_root backend_name variables_name kind; do
    root="$ROOT_DIR/$relative_root"
    case "$kind" in
      networking) pattern='\.aws_nat_gateway\.' ;;
      spoke) pattern='\.aws_ec2_transit_gateway_vpc_attachment\.' ;;
      hub) pattern='\.aws_ec2_transit_gateway\.' ;;
      cluster) pattern='\.aws_eks_cluster\.' ;;
      *) pattern='\.aws_iam_role\.' ;;
    esac
    if state_holds "$root" "$root/$backend_name" "$pattern"; then
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
    receipt=""
    volume_record=""
    if [[ "$direction" == "down" ]]; then
      [[ "${4:-}" == "--receipt" && -n "${5:-}" && "${6:-}" == "--volume-record" && -n "${7:-}" && -z "${8:-}" ]] || { usage; exit 2; }
      receipt=$5
      volume_record=$7
    else
      [[ -z "${4:-}" ]] || { usage; exit 2; }
    fi
    plan_profile "$profile" "$direction" "$receipt" "$volume_record"
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
  snapshot-volumes)
    profile=${2:-}
    validate_profile "$profile"
    consent=()
    set -- "${@:3}"
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "--consent" && -n "${2:-}" ]] || { usage; exit 2; }
      consent+=("$2")
      shift 2
    done
    snapshot_volumes "$profile" "${consent[@]}"
    ;;
  quiescence-receipt)
    profile=${2:-}
    validate_profile "$profile"
    [[ "${3:-}" == "--volume-record" && -n "${4:-}" && -z "${5:-}" ]] || { usage; exit 2; }
    quiescence_receipt "$profile" "$4"
    ;;
  *)
    usage
    exit 2
    ;;
esac
