#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTRYPOINT="$ROOT/scripts/aws-profile-lifecycle.sh"
DURABLE_DELETE_FILTER="$ROOT/scripts/aws-profile-durable-deletes.jq"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$ROOT/$1" ]] || fail "missing file: $1"
}

require_text() {
  local file=$1
  shift
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  local pattern=$1
  local message=$2
  grep -Eq -- "$pattern" "$ROOT/$file" || fail "$message"
}

reject_text() {
  local file=$1
  shift
  if [[ "${1:-}" == "--" ]]; then
    shift
  fi
  local pattern=$1
  local message=$2
  if grep -En -- "$pattern" "$ROOT/$file" >/dev/null; then
    fail "$message"
  fi
}

require_file "scripts/aws-profile-lifecycle.sh"
require_file "scripts/aws-profile-durable-deletes.jq"
require_file "docs/aws-profile-lifecycle.md"
require_file ".github/workflows/aws-dev-foundation-checks.yml"

[[ -x "$ENTRYPOINT" ]] || fail "scripts/aws-profile-lifecycle.sh is not executable"

for profile in economical full; do
  require_text "scripts/aws-profile-lifecycle.sh" "(^|[^a-z])${profile}([^a-z]|$)" \
    "wrapper is missing the ${profile} profile"
done

for direction in up down; do
  require_text "scripts/aws-profile-lifecycle.sh" "(^|[^a-z])${direction}([^a-z]|$)" \
    "wrapper is missing the ${direction} direction"
done

for command in check init plan inspect apply status snapshot-volumes; do
  require_text "scripts/aws-profile-lifecycle.sh" "^[[:space:]]*${command}\)" \
    "wrapper is missing the ${command} command"
done

require_text "scripts/aws-profile-lifecycle.sh" 'terraform[[:space:]]+-chdir=' \
  "wrapper must isolate every Terraform invocation with -chdir"
require_text "scripts/aws-profile-lifecycle.sh" -- '-input=false' \
  "wrapper must disable interactive Terraform input"
require_text "scripts/aws-profile-lifecycle.sh" -- '-lock-timeout=5m' \
  "wrapper plans must use the bounded state-lock timeout"
require_text "scripts/aws-profile-lifecycle.sh" -- '-out=' \
  "wrapper must save plans before apply"
require_text "scripts/aws-profile-lifecycle.sh" 'sha256sum' \
  "wrapper must checksum saved plans"
require_text "scripts/aws-profile-lifecycle.sh" 'gitops[_-]revision' \
  "wrapper must record GitOps quiescence evidence"
require_text "scripts/aws-profile-lifecycle.sh" 'get-caller-identity' \
  "wrapper must verify the active AWS identity"
require_text "scripts/aws-profile-lifecycle.sh" 'runtime_enabled=false' \
  "foundation shutdown must use the runtime boundary"
require_text "scripts/aws-profile-lifecycle.sh" 'plan[[:space:]]+-destroy' \
  "full shutdown must plan destruction of the ephemeral egress root"
require_text "scripts/aws-profile-lifecycle.sh" 'require_command[[:space:]]+grep' \
  "wrapper must preflight its portable grep dependency"
require_text "scripts/aws-profile-lifecycle.sh" 'grep[[:space:]]+-Eq' \
  "wrapper state checks must use portable extended grep"
reject_text "scripts/aws-profile-lifecycle.sh" '(^|[[:space:]])rg([[:space:]]|$)' \
  "wrapper must not require ripgrep for operator commands"
reject_text "scripts/aws-profile-lifecycle.sh" 'auto-approve|kubectl[[:space:]]+(apply|delete|patch|scale)' \
  "wrapper must not auto-approve Terraform or mutate GitOps-managed clusters"
require_text "scripts/aws-profile-lifecycle.sh" 'Name=tag-key,Values=ebs\.csi\.aws\.com/cluster,CSIVolumeName' \
  "wrapper must find persistent volumes by the tags the EBS CSI driver sets"
require_text "scripts/aws-profile-lifecycle.sh" 'ec2[[:space:]]+create-snapshot' \
  "wrapper must snapshot persistent volumes before GitOps quiescence"
require_text "scripts/aws-profile-lifecycle.sh" 'ec2[[:space:]]+wait[[:space:]]+snapshot-completed' \
  "wrapper must wait for volume snapshots to complete"
require_text "scripts/aws-profile-lifecycle.sh" -- '--volume-record' \
  "down plans must require a persistent-volume record"
reject_text "scripts/aws-profile-lifecycle.sh" 'kubectl' \
  "wrapper must never invoke kubectl (spec 003 FR-012)"
require_text "scripts/aws-profile-lifecycle.sh" 'jq[[:space:]]+-r[[:space:]]+-f[[:space:]]+"\$DURABLE_DELETE_FILTER"' \
  "wrapper must audit shutdown plans with the versioned durable-delete filter"
require_text ".github/workflows/aws-dev-foundation-checks.yml" "scripts/aws-profile-durable-deletes\\.jq" \
  "AWS foundation workflow must run when the durable-delete filter changes"

runtime_oidc_plan="$(jq -n '
  {
    resource_changes: [{
      address: "module.foundation.module.eks[0].aws_iam_openid_connect_provider.oidc_provider[0]",
      type: "aws_iam_openid_connect_provider",
      change: {
        actions: ["delete"],
        before: {url: "oidc.eks.us-east-1.amazonaws.com/id/example"}
      }
    }]
  }
')"
runtime_oidc_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$runtime_oidc_plan")"
[[ -z "$runtime_oidc_deleted" ]] || \
  fail "the cluster-scoped EKS OIDC provider must be removable with the runtime"

github_oidc_plan="$(jq -n '
  {
    resource_changes: [{
      address: "module.foundation.aws_iam_openid_connect_provider.github_actions[0]",
      type: "aws_iam_openid_connect_provider",
      change: {
        actions: ["delete"],
        before: {url: "token.actions.githubusercontent.com"}
      }
    }]
  }
')"
github_oidc_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$github_oidc_plan")"
[[ "$github_oidc_deleted" == "module.foundation.aws_iam_openid_connect_provider.github_actions[0]" ]] || \
  fail "the account-level GitHub Actions OIDC provider must remain protected"

ecr_plan="$(jq -n '
  {
    resource_changes: [{
      address: "module.foundation.aws_ecr_repository.services[\"auth-api\"]",
      type: "aws_ecr_repository",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
ecr_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$ecr_plan")"
[[ "$ecr_deleted" == 'module.foundation.aws_ecr_repository.services["auth-api"]' ]] || \
  fail "durable ECR repositories must remain protected"

# A relative bundle path is valid at the operator interface. Terraform's
# -chdir changes how it resolves a relative plan argument, so the wrapper must
# canonicalize the bundle before invoking `terraform show` or `terraform apply`.
relative_bundle=".aws-profile-plans/contract-relative-$$"
fixture_bundle="$ROOT/$relative_bundle"
fake_bin="$(mktemp -d)"
capture_dir="$(mktemp -d)"
cleanup_relative_bundle_fixture() {
  rm -rf "$fixture_bundle" "$fake_bin" "$capture_dir"
}
volume_sandbox="$(mktemp -d)"
volume_bin="$(mktemp -d)"
cleanup_lifecycle_fixtures() {
  cleanup_relative_bundle_fixture
  rm -rf "$volume_sandbox" "$volume_bin"
}
trap cleanup_lifecycle_fixtures EXIT

mkdir -p "$fixture_bundle"
printf 'contract plan\n' >"$fixture_bundle/dev.tfplan"
printf '%s\n' \
  $'format\t1' \
  $'profile\teconomical' \
  $'direction\tup' \
  $'account\t575172595729' \
  $'commit\tabcdef1' \
  $'gitops_revision\tabcdef1' \
  $'root\tdev\taws/environments/dev/foundation\tdev.tfplan' \
  >"$fixture_bundle/metadata.tsv"
(
  cd "$fixture_bundle"
  sha256sum dev.tfplan metadata.tsv >checksums.sha256
)
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "${1:-}" == version && "${2:-}" == -json ]]; then' \
  '  printf '\''{"terraform_version":"1.15.8"}\n'\''' \
  '  exit 0' \
  'fi' \
  '[[ "${1:-}" == -chdir=* ]] || exit 2' \
  'terraform_root="${1#-chdir=}"' \
  'if [[ "${2:-}" == state && "${3:-}" == pull ]]; then' \
  '  printf '\''{"version":4}\n'\''' \
  '  exit 0' \
  'fi' \
  'if [[ "${2:-}" == show ]]; then' \
  '  plan_argument="${3:-}"' \
  '  capture_name=inspect-plan-argument' \
  'elif [[ "${2:-}" == apply && "${3:-}" == -input=false ]]; then' \
  '  plan_argument="${4:-}"' \
  '  capture_name=apply-plan-argument' \
  'else' \
  '  exit 2' \
  'fi' \
  'resolved_plan="$plan_argument"' \
  '[[ "$resolved_plan" == /* ]] || resolved_plan="$terraform_root/$resolved_plan"' \
  '[[ -f "$resolved_plan" ]] || { printf "missing plan: %s\n" "$resolved_plan" >&2; exit 1; }' \
  'printf "%s\n" "$plan_argument" >"$LIFECYCLE_CAPTURE_DIR/$capture_name"' \
  >"$fake_bin/terraform"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ "${1:-}" == --version ]]; then' \
  '  printf "aws-cli/2.31.0 Python/3.13 Linux/amd64\n"' \
  'else' \
  '  printf "575172595729\n"' \
  'fi' \
  >"$fake_bin/aws"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'if [[ " $* " == *" rev-parse HEAD "* ]]; then printf "abcdef1\n"; fi' \
  'exit 0' \
  >"$fake_bin/git"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "operator:x:1000:1000::%s:/bin/bash\n" "$LIFECYCLE_TEST_HOME"' \
  >"$fake_bin/getent"
chmod +x "$fake_bin/terraform"
chmod +x "$fake_bin/aws" "$fake_bin/git" "$fake_bin/getent"

(
  cd "$ROOT"
  PATH="$fake_bin:$PATH" LIFECYCLE_CAPTURE_DIR="$capture_dir" \
    "$ENTRYPOINT" inspect "$relative_bundle" >/dev/null
)
inspect_plan_argument="$(<"$capture_dir/inspect-plan-argument")"
[[ "$inspect_plan_argument" == /* ]] || \
  fail "inspect must pass an absolute saved-plan path after Terraform -chdir"
(
  cd "$ROOT"
  AWS_PROFILE=contract PATH="$fake_bin:$PATH" \
    LIFECYCLE_CAPTURE_DIR="$capture_dir" LIFECYCLE_TEST_HOME="$capture_dir/home" \
    "$ENTRYPOINT" apply economical up "$relative_bundle" >/dev/null
)
apply_plan_argument="$(<"$capture_dir/apply-plan-argument")"
[[ "$apply_plan_argument" == /* ]] || \
  fail "apply must pass an absolute saved-plan path after Terraform -chdir"

# Persistent volumes (spec 003 FR-018 to FR-020). snapshot-volumes records a
# completed snapshot, or explicit consent, for every EBS CSI volume. A down plan
# accepts only a record that predates the GitOps quiescence commit and still
# covers every volume. The sandbox is a copy of the wrapper with real Git
# repositories and fake AWS and Terraform binaries, so nothing reaches AWS.
sandbox_ops="$volume_sandbox/ops"
sandbox_gitops="$volume_sandbox/microservice-app-gitops"
mkdir -p "$sandbox_ops/scripts" "$sandbox_ops/aws/environments/dev/foundation" "$sandbox_gitops"
cp "$ENTRYPOINT" "$DURABLE_DELETE_FILTER" "$sandbox_ops/scripts/"
cp "$ROOT/.terraform-version" "$ROOT/.gitignore" "$sandbox_ops/"
printf '%s\n' 'expected_account_id = "575172595729"' 'aws_region          = "us-east-1"' \
  >"$sandbox_ops/aws/environments/dev/foundation/dev.tfvars"
printf 'bucket = "contract"\n' >"$sandbox_ops/aws/environments/dev/foundation/dev.s3.tfbackend"
contract_git() {
  git -c user.name=contract -c user.email=contract@example.invalid -c commit.gpgsign=false "$@"
}
contract_git -C "$sandbox_ops" init -q
contract_git -C "$sandbox_ops" add -A
contract_git -C "$sandbox_ops" commit -q -m contract
now="$(date -u +%s)"
contract_git -C "$sandbox_gitops" init -q
GIT_COMMITTER_DATE="@$((now - 86400)) +0000" GIT_AUTHOR_DATE="@$((now - 86400)) +0000" \
  contract_git -C "$sandbox_gitops" commit -q --allow-empty -m 'quiescence merged before the record'
stale_revision="$(git -C "$sandbox_gitops" rev-parse HEAD)"
GIT_COMMITTER_DATE="@$((now + 3600)) +0000" GIT_AUTHOR_DATE="@$((now + 3600)) +0000" \
  contract_git -C "$sandbox_gitops" commit -q --allow-empty -m 'quiescence merged after the record'
quiescence_revision="$(git -C "$sandbox_gitops" rev-parse HEAD)"
git -C "$sandbox_gitops" update-ref refs/remotes/origin/main "$quiescence_revision"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$*" >>"$VOLUME_CAPTURE/aws.log"' \
  'case "$*" in' \
  '  --version) printf "aws-cli/2.31.0 Python/3.13 Linux/amd64\n" ;;' \
  '  "sts get-caller-identity"*) printf "575172595729\n" ;;' \
  '  *"ec2 describe-volumes"*)' \
  '    printf "vol-0aaa\t10\tpvc-prometheus\nvol-0bbb\t2\tpvc-grafana\n"' \
  '    if [[ -n "${EXTRA_VOLUME:-}" ]]; then printf "%s\t5\tpvc-new\n" "$EXTRA_VOLUME"; fi ;;' \
  '  *"ec2 create-snapshot"*) printf "snap-0aaa\n" ;;' \
  '  *"ec2 wait snapshot-completed"*) ;;' \
  '  *"ec2 describe-snapshots"*) printf "snap-0aaa\tcompleted\n" ;;' \
  '  *) exit 2 ;;' \
  'esac' \
  >"$volume_bin/aws"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "${1:-}" == version ]]; then printf '\''{"terraform_version":"1.15.8"}\n'\''; exit 0; fi' \
  '[[ "${1:-}" == -chdir=* ]] || exit 2' \
  'case "${2:-}" in' \
  '  init) ;;' \
  '  plan) for argument in "$@"; do [[ "$argument" != -out=* ]] || printf "plan\n" >"${argument#-out=}"; done ;;' \
  '  show) printf '\''{"resource_changes":[]}\n'\'' ;;' \
  '  *) exit 2 ;;' \
  'esac' \
  >"$volume_bin/terraform"
chmod +x "$volume_bin/aws" "$volume_bin/terraform"

in_sandbox() {
  (
    cd "$sandbox_ops"
    AWS_PROFILE=contract PATH="$volume_bin:$PATH" VOLUME_CAPTURE="$volume_sandbox" "$@"
  )
}

in_sandbox ./scripts/aws-profile-lifecycle.sh snapshot-volumes economical --consent vol-0bbb >/dev/null
volume_record="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'volumes-economical-*' | head -n 1)"
[[ -n "$volume_record" && -f "$volume_record/record.tsv" ]] || \
  fail "snapshot-volumes must write a volume record"
grep -Fxq $'volume\tvol-0aaa\tpvc-prometheus\t10\tsnapshot\tsnap-0aaa' "$volume_record/record.tsv" || \
  fail "the volume record must name the completed snapshot of each unconsented volume"
grep -Fxq $'volume\tvol-0bbb\tpvc-grafana\t2\tconsent\t-' "$volume_record/record.tsv" || \
  fail "the volume record must keep explicit consent instead of a snapshot"
[[ "$(grep -c 'ec2 create-snapshot' "$volume_sandbox/aws.log")" == 1 ]] || \
  fail "only volumes without consent may be snapshotted"
grep -Eq 'ec2 create-snapshot .*--volume-id vol-0aaa' "$volume_sandbox/aws.log" || \
  fail "the snapshot must come from the unconsented volume"
grep -Eq 'ec2 wait snapshot-completed .*snap-0aaa' "$volume_sandbox/aws.log" || \
  fail "snapshot-volumes must wait for its snapshots to complete"
(cd "$volume_record" && sha256sum -c --quiet checksums.sha256) || \
  fail "the volume record must be checksummed"

if in_sandbox ./scripts/aws-profile-lifecycle.sh snapshot-volumes economical --consent vol-0zzz >/dev/null 2>&1; then
  fail "consent naming a volume that does not exist must be rejected"
fi
if in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical down --gitops-revision "$quiescence_revision" >/dev/null 2>&1; then
  fail "a down plan without a volume record must be rejected"
fi
if output="$(in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical down \
  --gitops-revision "$stale_revision" --volume-record "$volume_record" 2>&1)"; then
  fail "a volume record newer than the GitOps quiescence commit must be rejected"
fi
grep -q 'predate' <<<"$output" || fail "the stale-record rejection must explain the ordering"
if in_sandbox env EXTRA_VOLUME=vol-0ccc ./scripts/aws-profile-lifecycle.sh plan economical down \
  --gitops-revision "$quiescence_revision" --volume-record "$volume_record" >/dev/null 2>&1; then
  fail "a volume missing from the record must block the down plan"
fi
in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical down \
  --gitops-revision "$quiescence_revision" --volume-record "$volume_record" >/dev/null || \
  fail "a record that predates quiescence and covers every volume must allow the down plan"
down_bundle="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'economical-down-*' | head -n 1)"
grep -q $'^volume_record\t' "$down_bundle/metadata.tsv" || \
  fail "the down bundle must record which volume record it relied on"
cmp -s "$volume_record/record.tsv" "$down_bundle/volume-record.tsv" || \
  fail "the down bundle must carry a copy of the volume record"
(cd "$down_bundle" && sha256sum -c --quiet checksums.sha256) || \
  fail "the down bundle checksums must cover the volume record"

for root in dev demo-full full-dev full-prod; do
  require_text "aws/environments/${root}/foundation/variables.tf" 'variable "runtime_enabled"' \
    "${root} root is missing runtime_enabled"
  require_text "aws/environments/${root}/foundation/main.tf" 'runtime_enabled[[:space:]]*=[[:space:]]*var\.runtime_enabled' \
    "${root} root does not pass runtime_enabled to the foundation module"
done

require_text "aws/modules/environment-foundation/variables.tf" 'variable "runtime_enabled"' \
  "foundation module is missing runtime_enabled"
require_text "aws/modules/environment-foundation/variables.tf" 'default[[:space:]]*=[[:space:]]*true' \
  "runtime_enabled must default on"
require_text "aws/modules/environment-foundation/outputs.tf" 'runtime_enabled[[:space:]]*=[[:space:]]*var\.runtime_enabled' \
  "foundation contract does not expose runtime state"

for durable_file in ecr.tf route53.tf github-oidc.tf; do
  reject_text "aws/modules/environment-foundation/${durable_file}" \
    '(count|for_each)[[:space:]]*=[^\n]*runtime_enabled' \
    "durable resources in ${durable_file} must not depend on runtime_enabled"
done
require_text "aws/modules/environment-foundation/managed-secrets.tf" \
  'resource "aws_secretsmanager_secret" "environment_jwt"' \
  "durable environment JWT secret containers are missing"
require_text "aws/modules/environment-foundation/managed-secrets.tf" \
  'resource "aws_secretsmanager_secret_version" "environment_jwt"' \
  "durable environment JWT secret values are missing"

printf 'PASS: AWS profile lifecycle contract\n'
