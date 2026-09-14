#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_ROOT="$ROOT_DIR/.aws-profile-plans"
GITOPS_DIR="$(cd "$ROOT_DIR/.." && pwd)/microservice-app-gitops"
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
  scripts/aws-profile-lifecycle.sh plan {economical|full} {up|down} [--gitops-revision REVISION --volume-record RECORD_DIRECTORY]
  scripts/aws-profile-lifecycle.sh inspect BUNDLE_DIRECTORY
  scripts/aws-profile-lifecycle.sh apply {economical|full} {up|down} BUNDLE_DIRECTORY
  scripts/aws-profile-lifecycle.sh status {economical|full}

Planning never applies. Applying accepts only an unchanged saved-plan bundle.
A down plan requires the commit of a reviewed, merged GitOps quiescence change and
a persistent-volume record that snapshot-volumes wrote before that change merged.
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

verify_gitops_revision() {
  local revision=$1
  [[ "$revision" =~ ^[0-9a-f]{7,40}$ ]] || fail "A down plan requires --gitops-revision with a Git commit SHA."
  [[ -d "$GITOPS_DIR/.git" ]] || fail "GitOps repository not found at $GITOPS_DIR."
  git -C "$GITOPS_DIR" cat-file -e "${revision}^{commit}" 2>/dev/null || \
    fail "GitOps revision $revision is not available in the local GitOps repository."
  git -C "$GITOPS_DIR" merge-base --is-ancestor "$revision" origin/main || \
    fail "GitOps revision $revision is not merged into the locally known origin/main. Fetch the GitOps repository and retry."
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
  printf 'Merge the GitOps quiescence change only now; plan-down rejects a record newer than that commit.\n'
}

# Prints the canonical record directory when the record is fit for a down plan.
verify_volume_record() {
  local profile=$1
  local gitops_revision=$2
  local supplied_record=$3
  local record region stored_profile stored_account created_epoch quiescence_epoch
  local volume size pv snapshot states
  local -a snapshots=()

  [[ -n "$supplied_record" && -d "$supplied_record" ]] || \
    fail "Volume record does not exist: ${supplied_record:-none}. Run snapshot-volumes before merging GitOps quiescence."
  record="$(cd "$supplied_record" && pwd -P)"
  require_file "$record/record.tsv"
  require_file "$record/checksums.sha256"
  (cd "$record" && sha256sum -c --quiet checksums.sha256) || fail "Volume record $record fails its checksum."

  stored_profile="$(record_value "$record" profile)"
  stored_account="$(record_value "$record" account)"
  region="$(record_value "$record" region)"
  created_epoch="$(record_value "$record" created_epoch)"
  [[ "$stored_profile" == "$profile" ]] || fail "Volume record profile is $stored_profile, not $profile."
  [[ "$stored_account" == "$(caller_account)" ]] || fail "Volume record account $stored_account is not the active AWS account."
  [[ "$region" == "$(profile_region "$profile")" ]] || fail "Volume record region $region is not the $profile region."
  quiescence_epoch="$(git -C "$GITOPS_DIR" show -s --format=%ct "$gitops_revision")"
  [[ "$created_epoch" =~ ^[0-9]+$ && "$created_epoch" -lt "$quiescence_epoch" ]] || \
    fail "Volume record $record must predate GitOps quiescence commit $gitops_revision. Snapshot the volumes before merging quiescence."

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

plan_profile() {
  local profile=$1
  local direction=$2
  local gitops_revision=$3
  local supplied_volume_record=${4:-}
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
    verify_gitops_revision "$gitops_revision"
    volume_record="$(verify_volume_record "$profile" "$gitops_revision" "$supplied_volume_record")"
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
    printf 'gitops_revision\t%s\n' "$gitops_revision"
    printf 'pass\t%s\n' "$pass"
    if [[ -n "$volume_record" ]]; then
      printf 'volume_record\t%s\n' "$volume_record"
    fi
  } >"$bundle/metadata.tsv"
  if [[ -n "$volume_record" ]]; then
    cp "$volume_record/record.tsv" "$bundle/volume-record.tsv"
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
          terraform -chdir="$root" plan "${plan_args[@]}" -var=cluster_deletion_protection=false
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
    sha256sum "${checksum_files[@]}" >checksums.sha256
  )
  printf 'Saved plan bundle: %s\n' "$bundle"
  case "$pass" in
    unprotect)
      printf 'A cluster refuses deletion, so this bundle only turns deletion protection off on each protected cluster.\n'
      printf 'Apply it, then plan down again with the same GitOps revision and volume record for the destroy bundle.\n'
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
  printf 'GitOps revision: %s\n' "$(metadata_value "$bundle" gitops_revision)"
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

apply_bundle() {
  local requested_profile=$1
  local requested_direction=$2
  local supplied_bundle=$3
  local bundle
  local stored_profile stored_direction stored_account stored_commit active_account
  local name relative_root plan_name root

  bundle="$(canonical_bundle_path "$supplied_bundle")"
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
    [[ -n "$(metadata_value "$bundle" volume_record)" && -f "$bundle/volume-record.tsv" ]] || \
      fail "The down bundle carries no persistent-volume record. Re-plan with --volume-record."
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
    gitops_revision=""
    volume_record=""
    if [[ "$direction" == "down" ]]; then
      [[ "${4:-}" == "--gitops-revision" && -n "${5:-}" && "${6:-}" == "--volume-record" && -n "${7:-}" && -z "${8:-}" ]] || { usage; exit 2; }
      gitops_revision=$5
      volume_record=$7
    else
      [[ -z "${4:-}" ]] || { usage; exit 2; }
    fi
    plan_profile "$profile" "$direction" "$gitops_revision" "$volume_record"
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
  *)
    usage
    exit 2
    ;;
esac
