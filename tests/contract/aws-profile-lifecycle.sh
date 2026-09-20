#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENTRYPOINT="$ROOT/scripts/aws-profile-lifecycle.sh"
DURABLE_DELETE_FILTER="$ROOT/scripts/aws-profile-durable-deletes.jq"
EGRESS_DELETE_FILTER="$ROOT/scripts/aws-profile-egress-deletes.jq"

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

# The variable block in FILE declares exactly this default.
require_variable_default() {
  local file=$1
  local variable=$2
  local value=$3
  local message=$4
  sed -n "/^variable \"${variable}\" {/,/^}/p" "$ROOT/$file" | \
    grep -Eq "^[[:space:]]*default[[:space:]]*=[[:space:]]*${value}[[:space:]]*$" || fail "$message"
}

require_file "scripts/aws-profile-lifecycle.sh"
require_file "scripts/aws-profile-durable-deletes.jq"
require_file "scripts/aws-profile-egress-deletes.jq"
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

for command in check init plan inspect apply status snapshot-volumes quiescence-receipt; do
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
reject_text "scripts/aws-profile-lifecycle.sh" '--gitops-revision' \
  "wrapper must not require a GitOps revision for down transitions"
require_text "scripts/aws-profile-lifecycle.sh" '--receipt' \
  "wrapper down plan must require a quiescence receipt"
require_text "scripts/aws-profile-lifecycle.sh" 'quiescence_receipt|quiescence-receipt' \
  "wrapper must record quiescence receipt evidence"
require_text "scripts/aws-profile-lifecycle.sh" 'post-destroy runtime sweep|sweep' \
  "wrapper must implement post-destroy runtime sweep"
require_text "scripts/aws-profile-lifecycle.sh" 'get-caller-identity' \
  "wrapper must verify the active AWS identity"
require_text "scripts/aws-profile-lifecycle.sh" 'plan[[:space:]]+-destroy' \
  "the clusters, the IRSA pass, and the egress hub must be planned for destruction"
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
require_text "scripts/aws-profile-lifecycle.sh" 'Snapshots\[0\]\.State' \
  "the sweep must query the recorded snapshot state explicitly"
require_text "scripts/aws-profile-lifecycle.sh" -- '--volume-record' \
  "down plans must require a persistent-volume record"
reject_text "scripts/aws-profile-lifecycle.sh" 'kubectl' \
  "wrapper must never invoke kubectl (spec 003 FR-012)"
require_text "scripts/aws-profile-lifecycle.sh" 'jq[[:space:]]+-r[[:space:]]+-f[[:space:]]+"\$DURABLE_DELETE_FILTER"' \
  "wrapper must audit shutdown plans with the versioned durable-delete filter"
require_text ".github/workflows/aws-dev-foundation-checks.yml" "scripts/aws-profile-durable-deletes\\.jq" \
  "AWS foundation workflow must run when the durable-delete filter changes"

# Both profiles map onto the rebuilt roots (spec 003 FR-021 to FR-025, FR-027 to FR-029).
require_text "scripts/aws-profile-lifecycle.sh" 'nat_gateways_enabled=false' \
  "the economical down transition must remove only the NAT egress of eco/networking"
require_text "scripts/aws-profile-lifecycle.sh" 'nat_gateways_enabled=true' \
  "the economical up transition must restore the NAT egress of eco/networking"
require_text "scripts/aws-profile-lifecycle.sh" 'transit_enabled=false' \
  "the full down transition must remove only the transit egress of each spoke"
require_text "scripts/aws-profile-lifecycle.sh" 'transit_enabled=true' \
  "the full up transition must restore the transit egress of each spoke"
require_text "scripts/aws-profile-lifecycle.sh" 'cluster_deletion_protection=false' \
  "a protected cluster must lose its deletion protection in a bundle of its own"
require_text "scripts/aws-profile-lifecycle.sh" 'jq[[:space:]]+-r[[:space:]]+-f[[:space:]]+"\$EGRESS_DELETE_FILTER"' \
  "wrapper must audit the networking down plans with the versioned egress filter"
require_text ".github/workflows/aws-dev-foundation-checks.yml" "scripts/aws-profile-egress-deletes\\.jq" \
  "AWS foundation workflow must run when the egress filter changes"
require_text "scripts/aws-profile-lifecycle.sh" 'config/aws-account\.env' \
  "wrapper must compare every root with the single declared AWS account"
reject_text "scripts/aws-profile-lifecycle.sh" 'expected_account_id|runtime_enabled' \
  "wrapper must not read the inputs of the retired foundation roots"
reject_text "scripts/aws-profile-lifecycle.sh" 'aws/environments/(dev|demo-full|full-dev|full-prod)/foundation|aws/shared/egress' \
  "wrapper must not plan the retired foundation and egress roots"
reject_text "scripts/aws-profile-lifecycle.sh" 'aws/environments/shd/(state|security|registry|dns)|aws/environments/(eco|fdev|fstg|fprd)/security\|' \
  "wrapper must never plan a root that holds persistent resources"

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

# The economical A aliases are runtime pointers to the shared ALB. GitOps removes
# that ALB before Terraform removes the cluster, so the aliases leave with the
# runtime while the hosted zone and ACM validation record remain durable.
runtime_ingress_alias_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_route53_record.ingress[\"eco.microtodosuite.online\"]",
      type: "aws_route53_record",
      change: {actions: ["delete"], before: {type: "A", alias: [{name: "example.elb.amazonaws.com"}]}}
    }]
  }
')"
runtime_ingress_alias_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$runtime_ingress_alias_plan")"
[[ -z "$runtime_ingress_alias_deleted" ]] || \
  fail "the economical ALB alias must be removable with the runtime"

certificate_validation_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_route53_record.certificate_validation[\"eco.microtodosuite.online\"]",
      type: "aws_route53_record",
      change: {actions: ["delete"], before: {type: "CNAME"}}
    }]
  }
')"
certificate_validation_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$certificate_validation_plan")"
[[ "$certificate_validation_deleted" == 'aws_route53_record.certificate_validation["eco.microtodosuite.online"]' ]] || \
  fail "the ACM validation record must remain protected"

secrets_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_secretsmanager_secret.jwt",
      type: "aws_secretsmanager_secret",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
secrets_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$secrets_plan")"
[[ "$secrets_deleted" == "aws_secretsmanager_secret.jwt" ]] || \
  fail "Secrets Manager secrets must remain protected"

acm_certificate_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_acm_certificate.ingress",
      type: "aws_acm_certificate",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
acm_certificate_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$acm_certificate_plan")"
[[ "$acm_certificate_deleted" == "aws_acm_certificate.ingress" ]] || \
  fail "ACM certificates must remain protected"

kms_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_kms_key.eks",
      type: "aws_kms_key",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
kms_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$kms_plan")"
[[ "$kms_deleted" == "aws_kms_key.eks" ]] || \
  fail "KMS keys must remain protected"

s3_state_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_s3_bucket.state",
      type: "aws_s3_bucket",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
s3_state_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$s3_state_plan")"
[[ "$s3_state_deleted" == "aws_s3_bucket.state" ]] || \
  fail "Terraform state bucket must remain protected"

# T016 companion families: every durable family must be unreachable as a whole,
# not just its primary resource (ACM certificate+validation, all Route53
# non-ALB-alias records, ECR repository/policy, Secrets secret/version, KMS
# key/alias/replica, S3 bucket companion resources, GitHub OIDC attachments).
acm_validation_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_acm_certificate_validation.ingress",
      type: "aws_acm_certificate_validation",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
acm_validation_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$acm_validation_plan")"
[[ "$acm_validation_deleted" == "aws_acm_certificate_validation.ingress" ]] || \
  fail "ACM certificate validations must remain protected"

kms_alias_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_kms_alias.eks",
      type: "aws_kms_alias",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
kms_alias_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$kms_alias_plan")"
[[ "$kms_alias_deleted" == "aws_kms_alias.eks" ]] || \
  fail "KMS aliases must remain protected"

kms_replica_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_kms_replica_key.eks",
      type: "aws_kms_replica_key",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
kms_replica_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$kms_replica_plan")"
[[ "$kms_replica_deleted" == "aws_kms_replica_key.eks" ]] || \
  fail "KMS replica keys must remain protected"

secrets_version_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_secretsmanager_secret_version.jwt",
      type: "aws_secretsmanager_secret_version",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
secrets_version_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$secrets_version_plan")"
[[ "$secrets_version_deleted" == "aws_secretsmanager_secret_version.jwt" ]] || \
  fail "Secrets Manager secret versions must remain protected"

ecr_policy_plan="$(jq -n '
  {
    resource_changes: [{
      address: "module.foundation.aws_ecr_repository_policy.services[\"auth-api\"]",
      type: "aws_ecr_repository_policy",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
ecr_policy_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$ecr_policy_plan")"
[[ "$ecr_policy_deleted" == 'module.foundation.aws_ecr_repository_policy.services["auth-api"]' ]] || \
  fail "ECR repository policies must remain protected"

s3_versioning_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_s3_bucket_versioning.state",
      type: "aws_s3_bucket_versioning",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
s3_versioning_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$s3_versioning_plan")"
[[ "$s3_versioning_deleted" == "aws_s3_bucket_versioning.state" ]] || \
  fail "Terraform state bucket versioning must remain protected"

s3_policy_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_s3_bucket_policy.state",
      type: "aws_s3_bucket_policy",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
s3_policy_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$s3_policy_plan")"
[[ "$s3_policy_deleted" == "aws_s3_bucket_policy.state" ]] || \
  fail "Terraform state bucket policies must remain protected"

s3_encryption_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_s3_bucket_server_side_encryption_configuration.state",
      type: "aws_s3_bucket_server_side_encryption_configuration",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
s3_encryption_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$s3_encryption_plan")"
[[ "$s3_encryption_deleted" == "aws_s3_bucket_server_side_encryption_configuration.state" ]] || \
  fail "Terraform state bucket encryption configuration must remain protected"

route53_zone_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_route53_zone.primary",
      type: "aws_route53_zone",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
route53_zone_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$route53_zone_plan")"
[[ "$route53_zone_deleted" == "aws_route53_zone.primary" ]] || \
  fail "Route53 hosted zones must remain protected"

route53_txt_plan="$(jq -n '
  {
    resource_changes: [{
      address: "aws_route53_record.delegation[\"eco.microtodosuite.online\"]",
      type: "aws_route53_record",
      change: {actions: ["delete"], before: {type: "TXT"}}
    }]
  }
')"
route53_txt_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$route53_txt_plan")"
[[ "$route53_txt_deleted" == 'aws_route53_record.delegation["eco.microtodosuite.online"]' ]] || \
  fail "Route53 non-alias records must remain protected"

github_attachment_plan="$(jq -n '
  {
    resource_changes: [{
      address: "module.foundation.aws_iam_role_policy_attachment.github_ecr_publisher",
      type: "aws_iam_role_policy_attachment",
      change: {actions: ["delete"], before: {}}
    }]
  }
')"
github_attachment_deleted="$(jq -r -f "$DURABLE_DELETE_FILTER" <<<"$github_attachment_plan")"
[[ "$github_attachment_deleted" == "module.foundation.aws_iam_role_policy_attachment.github_ecr_publisher" ]] || \
  fail "GitHub publisher attachments must remain protected"

# A networking down plan may delete its NAT or transit egress and nothing else.
egress_plan="$(jq -n '
  {
    resource_changes: [
      {address: "module.network.aws_nat_gateway.this[\"a\"]", type: "aws_nat_gateway", change: {actions: ["delete"]}},
      {address: "module.network.aws_eip.this[\"a\"]", type: "aws_eip", change: {actions: ["delete"]}},
      {address: "module.network.aws_route.private_nat[\"priva\"]", type: "aws_route", change: {actions: ["delete"]}},
      {address: "module.network.aws_route_table.private[\"priva\"]", type: "aws_route_table", change: {actions: ["no-op"]}}
    ]
  }
')"
egress_deleted="$(jq -r -f "$EGRESS_DELETE_FILTER" <<<"$egress_plan")"
[[ -z "$egress_deleted" ]] || \
  fail "the networking down plan must be allowed to delete the NAT gateways, their Elastic IPs, and their private routes"

transit_plan="$(jq -n '
  {
    resource_changes: [
      {address: "module.network.aws_ec2_transit_gateway_vpc_attachment.this[0]", type: "aws_ec2_transit_gateway_vpc_attachment", change: {actions: ["delete"]}},
      {address: "module.network.aws_ec2_transit_gateway_route_table_association.this[0]", type: "aws_ec2_transit_gateway_route_table_association", change: {actions: ["delete"]}},
      {address: "module.network.aws_ec2_transit_gateway_route.to_hub[0]", type: "aws_ec2_transit_gateway_route", change: {actions: ["delete"]}},
      {address: "module.network.aws_ec2_transit_gateway_route.hub_return[0]", type: "aws_ec2_transit_gateway_route", change: {actions: ["delete"]}},
      {address: "module.network.aws_route.private_transit[\"priva\"]", type: "aws_route", change: {actions: ["delete"]}}
    ]
  }
')"
transit_deleted="$(jq -r -f "$EGRESS_DELETE_FILTER" <<<"$transit_plan")"
[[ -z "$transit_deleted" ]] || \
  fail "a spoke down plan must be allowed to delete its transit attachment, association, transit routes, and private transit routes"

beyond_egress_plan="$(jq -n '
  {
    resource_changes: [
      {address: "module.network.aws_route.public_internet", type: "aws_route", change: {actions: ["delete"]}},
      {address: "module.network.aws_subnet.this[\"priva\"]", type: "aws_subnet", change: {actions: ["delete", "create"]}},
      {address: "module.transit_egress.aws_ec2_transit_gateway_route_table.spoke[\"fdev\"]", type: "aws_ec2_transit_gateway_route_table", change: {actions: ["delete"]}}
    ]
  }
')"
beyond_egress_deleted="$(jq -r -f "$EGRESS_DELETE_FILTER" <<<"$beyond_egress_plan")"
[[ "$beyond_egress_deleted" == $'module.network.aws_route.public_internet\nmodule.network.aws_subnet.this["priva"]\nmodule.transit_egress.aws_ec2_transit_gateway_route_table.spoke["fdev"]' ]] || \
  fail "a networking down plan that deletes the public route, replaces a subnet, or deletes a transit route table must be rejected"

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
printf 'contract plan\n' >"$fixture_bundle/eco-networking.tfplan"
printf '%s\n' \
  $'format\t1' \
  $'profile\teconomical' \
  $'direction\tup' \
  $'account\t575172595729' \
  $'commit\tabcdef1' \
  $'root\teco-networking\taws/environments/eco/networking\teco-networking.tfplan' \
  >"$fixture_bundle/metadata.tsv"
(
  cd "$fixture_bundle"
  sha256sum eco-networking.tfplan metadata.tsv >checksums.sha256
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

# Capacity limit L1 (decision D2 as amended on 2026-09-13): the wrapper reads the
# Region's VPCs-per-Region quota before an up transition plans anything.
require_text "scripts/aws-profile-lifecycle.sh" 'quota-code L-F678F1CE' \
  "an up transition must read the VPCs-per-Region quota before it plans (capacity limit L1)"

# The sandbox is a copy of the wrapper with the runtime roots of both profiles,
# real Git repositories, and fake AWS and Terraform binaries, so nothing reaches
# AWS. The fake Terraform logs every call as "<environment>/<domain> <arguments>".
# CLUSTER_PROTECTION unset means no cluster root's state holds a cluster; true or
# false is the deletion protection of the cluster each holds. HUB_PRESENT set
# means shd/networking's state holds the transit gateway. PLAN_JSON replaces
# every saved plan's JSON. VPC_COUNT is how many VPCs the Region holds (1 when
# unset), and SPOKES_PRESENT set means every networking root's state holds its VPC.
sandbox_ops="$volume_sandbox/ops"
sandbox_gitops="$volume_sandbox/microservice-app-gitops"
terraform_log="$volume_sandbox/terraform.log"
mkdir -p "$sandbox_ops/scripts" "$sandbox_ops/config" "$sandbox_gitops"
cp "$ENTRYPOINT" "$DURABLE_DELETE_FILTER" "$EGRESS_DELETE_FILTER" "$sandbox_ops/scripts/"
cp "$ROOT/.terraform-version" "$ROOT/.gitignore" "$sandbox_ops/"
printf 'AWS_ACCOUNT_ID=575172595729\n' >"$sandbox_ops/config/aws-account.env"
for root in eco/networking eco/workload eco/security-irsa shd/networking \
  fdev/networking fdev/workload fdev/security-irsa fstg/networking fstg/workload fstg/security-irsa \
  fprd/networking fprd/workload fprd/security-irsa; do
  environment="${root%%/*}"
  domain="${root##*/}"
  mkdir -p "$sandbox_ops/aws/environments/$root"
  printf '%s\n' 'aws_account_id = "575172595729"' 'aws_region     = "us-east-1"' \
    'client           = "lex"' 'project          = "mts"' "environment      = \"$environment\"" \
    >"$sandbox_ops/aws/environments/$root/$environment.tfvars"
  printf 'bucket = "contract"\n' >"$sandbox_ops/aws/environments/$root/$domain.s3.tfbackend"
done
contract_git() {
  git -c user.name=contract -c user.email=contract@example.invalid -c commit.gpgsign=false "$@"
}
contract_git -C "$sandbox_ops" init -q
contract_git -C "$sandbox_ops" add -A
contract_git -C "$sandbox_ops" commit -q -m contract

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\n" "$*" >>"$VOLUME_CAPTURE/aws.log"' \
  'if [[ -n "${DESCRIBE_DENY:-}" && "$*" == *"describe-${DESCRIBE_DENY}"* ]]; then' \
  '  printf "An error occurred (AccessDenied) when calling the Describe operation: denied\n" >&2; exit 254; fi' \
  'if [[ -n "${DESCRIBE_THROTTLE:-}" && "$*" == *"describe-${DESCRIBE_THROTTLE}"* ]]; then' \
  '  printf "An error occurred (Throttling) when calling the Describe operation: rate exceeded\n" >&2; exit 254; fi' \
  'case "$*" in' \
  '  --version) printf "aws-cli/2.31.0 Python/3.13 Linux/amd64\n" ;;' \
  '  "sts get-caller-identity"*) printf "575172595729\n" ;;' \
  '  *"ec2 describe-volumes"*--output\ text*)' \
  '    printf "vol-0aaa\t10\tpvc-prometheus\nvol-0bbb\t2\tpvc-grafana\n"' \
  '    if [[ -n "${EXTRA_VOLUME:-}" ]]; then printf "%s\t5\tpvc-new\n" "$EXTRA_VOLUME"; fi ;;' \
  '  *"ec2 create-snapshot"*) printf "snap-0aaa\n" ;;' \
  '  *"ec2 wait snapshot-completed"*) ;;' \
  '  *"ec2 describe-snapshots"*)' \
  '    [[ "$*" == *"--query"* ]] || { printf "ERROR: snapshot state query is required\n" >&2; exit 98; };' \
  '    if [[ "$*" == *"Snapshots[0].State"* ]]; then printf "%s\n" "${SNAP_STATE:-completed}"; else printf "snap-0aaa\t%s\n" "${SNAP_STATE:-completed}"; fi ;;' \
  '  *"ec2 describe-vpcs"*) printf "%s\n" "${VPC_COUNT:-1}" ;;' \
  '  *"service-quotas get-service-quota"*) printf "5.0\n" ;;' \
  '  *"elbv2 describe-load-balancers"*--output\ json*)' \
  '    if [[ -n "${SWEEP_EMPTY:-}" ]]; then printf "{\"LoadBalancers\":[]}\n";' \
  '    else printf "{\"LoadBalancers\":[{\"LoadBalancerArn\":\"arn:aws:elasticloadbalancing:us-east-1:575172595729:loadbalancer/app/k8s-eco-alb/1234567890abcdef\",\"Type\":\"application\"}]}\n"; fi ;;' \
  '  *"elbv2 describe-tags"*--output\ json*)' \
  '    if [[ -n "${SWEEP_GONE:-}" ]]; then printf "{\"TagDescriptions\":[]}\n";' \
  '    elif [[ "${TAG_MODE:-normal}" == "malformed" ]]; then printf "{{{not json\n";' \
  '    else' \
  '      case "${TAG_MODE:-normal}" in' \
  '        wrong-cluster) tag_value="lex-mts-fprd-eks-main" ;;' \
  '        missing) tag_value="" ;;' \
  '        *) tag_value="lex-mts-eco-eks-main" ;;' \
  '      esac;' \
  '      case "$*" in' \
  '        *loadbalancer/app*) resource_arn="arn:aws:elasticloadbalancing:us-east-1:575172595729:loadbalancer/app/k8s-eco-alb/1234567890abcdef" ;;' \
  '        *listener/app*) resource_arn="arn:aws:elasticloadbalancing:us-east-1:575172595729:listener/app/k8s-eco-alb/1234567890abcdef/9876543210fedcba" ;;' \
  '        *targetgroup*) resource_arn="arn:aws:elasticloadbalancing:us-east-1:575172595729:targetgroup/k8s-eco-tg/1234567890abcdef" ;;' \
  '        *) resource_arn="unknown" ;;' \
  '      esac;' \
  '      if [[ -z "$tag_value" ]]; then printf "{\"TagDescriptions\":[{\"ResourceArn\":\"%s\",\"Tags\":[]}]}\n" "$resource_arn";' \
  '      else printf "{\"TagDescriptions\":[{\"ResourceArn\":\"%s\",\"Tags\":[{\"Key\":\"elbv2.k8s.aws/cluster\",\"Value\":\"%s\"}]}]}\n" "$resource_arn" "$tag_value"; fi;' \
  '    fi ;;' \
  '  *"elbv2 describe-listeners"*--output\ json*)' \
  '    if [[ -n "${SWEEP_EMPTY:-}" ]]; then printf "{\"Listeners\":[]}\n";' \
  '    else printf "{\"Listeners\":[{\"ListenerArn\":\"arn:aws:elasticloadbalancing:us-east-1:575172595729:listener/app/k8s-eco-alb/1234567890abcdef/9876543210fedcba\"}]}\n"; fi ;;' \
  '  *"elbv2 describe-target-groups"*--output\ json*)' \
  '    if [[ -n "${SWEEP_EMPTY:-}" ]]; then printf "{\"TargetGroups\":[]}\n";' \
  '    else printf "{\"TargetGroups\":[{\"TargetGroupArn\":\"arn:aws:elasticloadbalancing:us-east-1:575172595729:targetgroup/k8s-eco-tg/1234567890abcdef\",\"TargetGroupName\":\"k8s-eco-tg\"}]}\n"; fi ;;' \
  '  *"ec2 describe-security-groups"*--output\ json*)' \
  '    if [[ -n "${SWEEP_EMPTY:-}" ]]; then printf "{\"SecurityGroups\":[]}\n";' \
  '    elif [[ "${TAG_MODE:-normal}" == "malformed" ]]; then printf "{{{not json\n";' \
  '    else' \
  '      case "${TAG_MODE:-normal}" in' \
  '        wrong-cluster) tag_value="lex-mts-fprd-eks-main" ;;' \
  '        missing) tag_value="" ;;' \
  '        *) tag_value="lex-mts-eco-eks-main" ;;' \
  '      esac;' \
  '      if [[ -z "$tag_value" ]]; then printf "{\"SecurityGroups\":[{\"GroupId\":\"sg-0123456789abcdef0\",\"GroupName\":\"k8s-elb-eco\",\"Tags\":[]}]}\n";' \
  '      else printf "{\"SecurityGroups\":[{\"GroupId\":\"sg-0123456789abcdef0\",\"GroupName\":\"k8s-elb-eco\",\"Tags\":[{\"Key\":\"elbv2.k8s.aws/cluster\",\"Value\":\"%s\"}]}]}\n" "$tag_value"; fi;' \
  '    fi ;;' \
  '  *"ec2 describe-network-interfaces"*--output\ json*)' \
  '    if [[ -n "${SWEEP_EMPTY:-}" ]]; then printf "{\"NetworkInterfaces\":[]}\n";' \
  '    elif [[ "${TAG_MODE:-normal}" == "malformed" ]]; then printf "{{{not json\n";' \
  '    else' \
  '      case "${TAG_MODE:-normal}" in' \
  '        wrong-cluster) tag_value="lex-mts-fprd-eks-main" ;;' \
  '        missing) tag_value="" ;;' \
  '        *) tag_value="lex-mts-eco-eks-main" ;;' \
  '      esac;' \
  '      if [[ -z "$tag_value" ]]; then printf "{\"NetworkInterfaces\":[{\"NetworkInterfaceId\":\"eni-0123456789abcdef0\",\"Status\":\"%s\",\"TagSet\":[]}]}\n" "${ENI_STATUS:-available}";' \
  '      else printf "{\"NetworkInterfaces\":[{\"NetworkInterfaceId\":\"eni-0123456789abcdef0\",\"Status\":\"%s\",\"TagSet\":[{\"Key\":\"elbv2.k8s.aws/cluster\",\"Value\":\"%s\"}]}]}\n" "${ENI_STATUS:-available}" "$tag_value"; fi;' \
  '    fi ;;' \
  '  *"ec2 describe-volumes"*--output\ json*)' \
  '    if [[ -n "${SWEEP_EMPTY:-}" ]]; then printf "{\"Volumes\":[]}\n";' \
  '    elif [[ "${TAG_MODE:-normal}" == "malformed" ]]; then printf "{{{not json\n";' \
  '    else' \
  '      case "${TAG_MODE:-normal}" in' \
  '        wrong-cluster) tag_value="lex-mts-fprd-eks-main" ;;' \
  '        missing) tag_value="" ;;' \
  '        *) tag_value="lex-mts-eco-eks-main" ;;' \
  '      esac;' \
  '      case "${TAG_MODE:-normal}" in' \
  '        generic-volume) volume_tags="{\"Key\":\"ebs.csi.aws.com/cluster\",\"Value\":\"true\"}" ;;' \
  '        k8s-owned-volume) volume_tags="{\"Key\":\"kubernetes.io/cluster/lex-mts-eco-eks-main\",\"Value\":\"owned\"}" ;;' \
  '        missing) volume_tags="" ;;' \
  '        *) volume_tags="{\"Key\":\"ebs.csi.aws.com/cluster\",\"Value\":\"$tag_value\"},{\"Key\":\"kubernetes.io/created-for/pv/name\",\"Value\":\"pvc-prometheus\"}" ;;' \
  '      esac;' \
  '      printf "{\"Volumes\":[{\"VolumeId\":\"vol-0aaa\",\"State\":\"%s\",\"Tags\":[%s]},{\"VolumeId\":\"vol-0bbb\",\"State\":\"in-use\",\"Tags\":[%s]}]}\n" "${VOL_STATE:-available}" "$volume_tags" "$volume_tags";' \
  '    fi ;;' \
  '  *"elbv2 describe-load-balancers"*)' \
  '    printf "arn:aws:elasticloadbalancing:us-east-1:575172595729:loadbalancer/app/k8s-eco-alb/1234567890abcdef\n" ;;' \
  '  *"elbv2 describe-tags"*loadbalancer*)' \
  '    printf "TagDescriptions:\n- ResourceArn: arn:aws:elasticloadbalancing:us-east-1:575172595729:loadbalancer/app/k8s-eco-alb/1234567890abcdef\n  Tags:\n  - Key: elbv2.k8s.aws/cluster\n    Value: lex-mts-eco-eks-main\n" ;;' \
  '  *"elbv2 describe-listeners"*)' \
  '    printf "arn:aws:elasticloadbalancing:us-east-1:575172595729:listener/app/k8s-eco-alb/1234567890abcdef/9876543210fedcba\n" ;;' \
  '  *"elbv2 describe-target-groups"*)' \
  '    printf "arn:aws:elasticloadbalancing:us-east-1:575172595729:targetgroup/k8s-eco-tg/1234567890abcdef\n" ;;' \
  '  *"elbv2 describe-tags"*targetgroup*)' \
  '    printf "TagDescriptions:\n- ResourceArn: arn:aws:elasticloadbalancing:us-east-1:575172595729:targetgroup/k8s-eco-tg/1234567890abcdef\n  Tags:\n  - Key: elbv2.k8s.aws/cluster\n    Value: lex-mts-eco-eks-main\n" ;;' \
  '  *"ec2 describe-security-groups"*)' \
  '    printf "sg-0123456789abcdef0\tk8s-elb-eco\telbv2.k8s.aws/cluster=lex-mts-eco-eks-main\n" ;;' \
  '  *"ec2 describe-network-interfaces"*)' \
  '    printf "eni-0123456789abcdef0\tavailable\telbv2.k8s.aws/cluster=lex-mts-eco-eks-main\n" ;;' \
  '  *"elbv2 delete-listener"*)' \
  '    if [[ -n "${SWEEP_GONE:-}" ]]; then printf "An error occurred (ListenerNotFound) when calling the DeleteListener operation: not found\n" >&2; exit 254; fi ;;' \
  '  *"elbv2 delete-load-balancer"*)' \
  '    if [[ "${SWEEP_HARD_FAIL:-}" == *load-balancer* ]]; then printf "An error occurred (UnauthorizedOperation) when calling the DeleteLoadBalancer operation: denied\n" >&2; exit 254; fi;' \
  '    if [[ -n "${SWEEP_GONE:-}" ]]; then printf "An error occurred (LoadBalancerNotFound) when calling the DeleteLoadBalancer operation: not found\n" >&2; exit 254; fi ;;' \
  '  *"elbv2 wait load-balancers-deleted"*)' \
  '    if [[ "${SWEEP_HARD_FAIL:-}" == *wait* ]]; then printf "Waiter encountered a terminal failure state\n" >&2; exit 1; fi ;;' \
  '  *"elbv2 delete-target-group"*)' \
  '    if [[ -n "${SWEEP_GONE:-}" ]]; then printf "An error occurred (TargetGroupNotFound) when calling the DeleteTargetGroup operation: not found\n" >&2; exit 254; fi ;;' \
  '  *"ec2 delete-security-group"*)' \
  '    if [[ -n "${SWEEP_GONE:-}" ]]; then printf "An error occurred (InvalidGroup.NotFound) when calling the DeleteSecurityGroup operation: not found\n" >&2; exit 254; fi ;;' \
  '  *"ec2 delete-volume"*)' \
  '    if [[ -n "${SWEEP_FAIL_ONCE:-}" && ! -f "$VOLUME_CAPTURE/sweep-fail-once.done" ]]; then : >"$VOLUME_CAPTURE/sweep-fail-once.done"; printf "An error occurred (VolumeInUse) when calling the DeleteVolume operation: in use\n" >&2; exit 1; fi;' \
  '    if [[ -n "${SWEEP_GONE:-}" ]]; then printf "An error occurred (InvalidVolume.NotFound) when calling the DeleteVolume operation: not found\n" >&2; exit 254; fi ;;' \
  '  *"ec2 delete-network-interface"*)' \
  '    if [[ -n "${SWEEP_GONE:-}" ]]; then printf "An error occurred (InvalidNetworkInterfaceID.NotFound) when calling the DeleteNetworkInterface operation: not found\n" >&2; exit 254; fi ;;' \
  '  *"acm delete-certificate"*|*"route53 change-resource-record-sets"*|*"ecr delete-repository"*|*"secretsmanager delete-secret"*|*"kms schedule-key-deletion"*|*"s3api delete-bucket"*|*"iam delete-open-id-connect-provider"*)' \
  '    printf "ERROR: protected resource type deletion attempted: %s\n" "$*" >&2; exit 99 ;;' \
  '  *) exit 2 ;;' \
  'esac' \
  >"$volume_bin/aws"
cat >"$volume_bin/terraform" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == version ]]; then printf '{"terraform_version":"1.15.8"}\n'; exit 0; fi
[[ "${1:-}" == -chdir=* ]] || exit 2
root="${1#-chdir=}"
root="$(basename "$(dirname "$root")")/$(basename "$root")"
printf '%s %s\n' "$root" "${*:2}" >>"$VOLUME_CAPTURE/terraform.log"
case "${2:-}" in
  init) ;;
  plan)
    for argument in "$@"; do
      [[ "$argument" != -out=* ]] || printf 'plan\n' >"${argument#-out=}"
    done
    ;;
  show)
    if [[ $# -gt 3 ]]; then
      plan_json="${PLAN_JSON:-}"
      [[ -n "$plan_json" ]] || plan_json='{"resource_changes":[]}'
      printf '%s\n' "$plan_json"
    elif [[ "$root" == */workload && -n "${CLUSTER_PROTECTION:-}" ]]; then
      printf '{"values":{"root_module":{"child_modules":[{"address":"module.eks_cluster","resources":[{"address":"module.eks_cluster.aws_eks_cluster.this","mode":"managed","type":"aws_eks_cluster","values":{"deletion_protection":%s}}]}]}}}\n' "$CLUSTER_PROTECTION"
    else
      printf '{"format_version":"1.0"}\n'
    fi
    ;;
  state)
    if [[ "$root" == */workload && -n "${CLUSTER_PROTECTION:-}" ]]; then
      printf 'module.eks_cluster.aws_eks_cluster.this\n'
    elif [[ "$root" == shd/networking && -n "${HUB_PRESENT:-}" ]]; then
      printf 'module.egress_network.aws_vpc.this\nmodule.transit_egress.aws_ec2_transit_gateway.this\n'
    elif [[ "$root" == */networking && -n "${SPOKES_PRESENT:-}" ]]; then
      printf 'module.network.aws_vpc.this\n'
    fi
    ;;
  apply) ;;
  *) exit 2 ;;
esac
FAKE
chmod +x "$volume_bin/aws" "$volume_bin/terraform"

in_sandbox() {
  (
    cd "$sandbox_ops"
    AWS_PROFILE=contract PATH="$volume_bin:$PATH" VOLUME_CAPTURE="$volume_sandbox" "$@"
  )
}

# Each transition starts from no saved bundle and an empty Terraform log, so two
# plans created within the same second cannot share a bundle directory.
fresh_transition() {
  rm -rf "$sandbox_ops"/.aws-profile-plans/economical-* "$sandbox_ops"/.aws-profile-plans/full-*
  : >"$terraform_log"
}

latest_bundle() {
  find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name "$1-$2-*" | sort | tail -n 1
}

bundle_roots() {
  awk -F '\t' '$1 == "root" { print $2 }' "$1/metadata.tsv" | paste -sd ' ' -
}

# A profile's roots are ready only when each names the declared account (spec
# 003 FR-025).
for profile in economical full; do
  in_sandbox ./scripts/aws-profile-lifecycle.sh check "$profile" >/dev/null || \
    fail "the $profile profile must be ready when every root names the declared account"
done
workload_variables="$sandbox_ops/aws/environments/eco/workload/eco.tfvars"
cp "$workload_variables" "$volume_sandbox/eco.tfvars.saved"
other_account="$(printf '4%.0s' 1 2 3 4 5 6 7 8 9 10 11 12)"
printf '%s\n' "aws_account_id = \"$other_account\"" 'aws_region     = "us-east-1"' >"$workload_variables"
if output="$(in_sandbox ./scripts/aws-profile-lifecycle.sh check economical 2>&1)"; then
  fail "a root whose aws_account_id differs from config/aws-account.env must be rejected"
fi
grep -Fq 'config/aws-account.env' <<<"$output" || \
  fail "the account rejection must name the single declaration"
cp "$volume_sandbox/eco.tfvars.saved" "$workload_variables"

# Persistent volumes (spec 003 FR-018 to FR-020). snapshot-volumes records a
# completed snapshot, or explicit consent, for every EBS CSI volume.
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

# Quiescence receipt replaces --gitops-revision with checksummed JSON evidence (spec 003 T016).
if in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical down --volume-record "$volume_record" >/dev/null 2>&1; then
  fail "a down plan without a quiescence receipt must be rejected"
fi

in_sandbox ./scripts/aws-profile-lifecycle.sh quiescence-receipt economical --volume-record "$volume_record" >/dev/null
quiescence_receipt="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'quiescence-economical-*' | head -n 1)"
[[ -n "$quiescence_receipt" && -f "$quiescence_receipt/receipt.json" ]] || \
  fail "quiescence-receipt must write a receipt.json"
(cd "$quiescence_receipt" && sha256sum -c --quiet checksums.sha256) || \
  fail "the quiescence receipt must be checksummed"
[[ "$(jq -r '.format' "$quiescence_receipt/receipt.json")" == "1" ]] || \
  fail "quiescence receipt must have format 1"
[[ "$(jq -r '.profile' "$quiescence_receipt/receipt.json")" == "economical" ]] || \
  fail "quiescence receipt must record profile"
[[ "$(jq -r '.account' "$quiescence_receipt/receipt.json")" == "575172595729" ]] || \
  fail "quiescence receipt must record account"
[[ "$(jq -r '.region' "$quiescence_receipt/receipt.json")" == "us-east-1" ]] || \
  fail "quiescence receipt must record region"
jq -e '.inventory.load_balancers and .inventory.target_groups and .inventory.security_groups and .inventory.volumes and .inventory.network_interfaces' "$quiescence_receipt/receipt.json" >/dev/null || \
  fail "quiescence receipt must include dry-run inventory across all in-scope resource types"

# Ordering guard: the volume record must predate the receipt.
stale_receipt_dir="$sandbox_ops/.aws-profile-plans/quiescence-economical-stale"
mkdir -p "$stale_receipt_dir"
jq '.created_epoch = 1000' "$quiescence_receipt/receipt.json" >"$stale_receipt_dir/receipt.json"
(cd "$stale_receipt_dir" && sha256sum receipt.json >checksums.sha256)
if output="$(in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$stale_receipt_dir" --volume-record "$volume_record" 2>&1)"; then
  fail "a volume record created after the quiescence receipt must be rejected"
fi
grep -q 'predate' <<<"$output" || fail "the stale-receipt rejection must explain the ordering"

if in_sandbox env EXTRA_VOLUME=vol-0ccc ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$quiescence_receipt" --volume-record "$volume_record" >/dev/null 2>&1; then
  fail "a volume missing from the record must block the down plan"
fi

# Economical down against an unprotected cluster destroys the IRSA pass, then the
# cluster, then removes only the NAT egress; eco/networking keeps its VPC
# (FR-022, FR-023).
fresh_transition
in_sandbox env CLUSTER_PROTECTION=false ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$quiescence_receipt" --volume-record "$volume_record" >/dev/null || \
  fail "a valid receipt and volume record must allow the down plan"
down_bundle="$(latest_bundle economical down)"
[[ "$(bundle_roots "$down_bundle")" == "eco-security-irsa eco-workload eco-networking" ]] || \
  fail "the down bundle must destroy the IRSA pass, then the cluster, then remove the NAT egress"
grep -Eq '^eco/security-irsa plan -destroy ' "$terraform_log" || \
  fail "the IRSA pass must be planned for destruction"
grep -Eq '^eco/workload plan -destroy ' "$terraform_log" || \
  fail "an unprotected cluster must be planned for destruction"
grep -Eq '^eco/workload plan -destroy .* -target=module\.eks_cluster([[:space:]]|$)' "$terraform_log" || \
  fail "the economical cluster destroy must target the EKS module"
grep -Eq '^eco/workload plan -destroy .* -target=module\.bootstrap_node_group([[:space:]]|$)' "$terraform_log" || \
  fail "the economical cluster destroy must target the bootstrap node module"
grep -Eq '^eco/workload plan -destroy .* -target=aws_route53_record\.ingress([[:space:]]|$)' "$terraform_log" || \
  fail "the economical cluster destroy must remove only the runtime ingress aliases"
grep -Eq '^eco/networking plan .*-var=nat_gateways_enabled=false' "$terraform_log" || \
  fail "eco/networking must be planned without its NAT gateways"
if grep -Eq '^eco/networking plan -destroy' "$terraform_log"; then
  fail "eco/networking must never be destroyed: its VPC holds eco/security's security groups"
fi
grep -q $'^volume_record\t' "$down_bundle/metadata.tsv" || \
  fail "the down bundle must record which volume record it relied on"
grep -q $'^receipt\t' "$down_bundle/metadata.tsv" || \
  fail "the down bundle must record which receipt it relied on"
cmp -s "$volume_record/record.tsv" "$down_bundle/volume-record.tsv" || \
  fail "the down bundle must carry a copy of the volume record"
(cd "$down_bundle" && sha256sum -c --quiet checksums.sha256) || \
  fail "the down bundle checksums must cover the volume record"

# Apply down executes the runtime sweep BETWEEN cluster destruction and networking (T016).
# It must delete allow-listed resources, verify completed snapshots before deleting volumes,
# never touch protected types, and be idempotent.
: >"$volume_sandbox/aws.log"
: >"$terraform_log"
in_sandbox ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" >/dev/null || \
  fail "apply down must execute successfully"

# Verify ordering: eco/workload apply -> sweep deletes -> eco/networking apply
workload_apply_line="$(grep -n '^eco/workload apply' "$terraform_log" | cut -d: -f1)"
networking_apply_line="$(grep -n '^eco/networking apply' "$terraform_log" | cut -d: -f1)"
[[ -n "$workload_apply_line" && -n "$networking_apply_line" && "$workload_apply_line" -lt "$networking_apply_line" ]] || \
  fail "workload cluster must be destroyed before networking plan is applied"
grep -q 'delete-load-balancer' "$volume_sandbox/aws.log" || \
  fail "apply down sweep must delete the in-cluster load balancer"
grep -q 'delete-volume' "$volume_sandbox/aws.log" || \
  fail "apply down sweep must delete PVC volumes"
grep -q 'delete-security-group' "$volume_sandbox/aws.log" || \
  fail "apply down sweep must delete controller security groups"
grep -q 'delete-network-interface' "$volume_sandbox/aws.log" || \
  fail "apply down sweep must delete orphaned ENIs"

# Verify protected types were never touched regardless of tags:
for protected_action in 'delete-certificate' 'change-resource-record-sets' 'delete-repository' 'delete-secret' 'schedule-key-deletion' 'delete-bucket' 'delete-open-id-connect-provider'; do
  if grep -q "$protected_action" "$volume_sandbox/aws.log"; then
    fail "protected action $protected_action was called during runtime sweep"
  fi
done

# T016 hardening: the sweep implementation must require exact current cluster
# ownership tags for every swept type, revalidate before each delete, tolerate
# only verified not-found states, keep protected families unreachable, bind the
# receipt to profile/account/region/cluster-set/volume-record, order volume
# record before receipt truthfully, emit one ordered event log with the sweep
# between workload and networking applies, and rerun cleanly after failure.
require_text "scripts/aws-profile-lifecycle.sh" 'owns_cluster_tag' \
  "wrapper must parse exact cluster tag key/value pairs instead of grepping substrings"
require_text "scripts/aws-profile-lifecycle.sh" 'owns_controller_tag' \
  "wrapper must prove controller ownership before deleting load-balancer security groups"
require_text "scripts/aws-profile-lifecycle.sh" 'sweep_target_type' \
  "wrapper must classify sweep targets through an explicit type allow-list, not name heuristics"
require_text "scripts/aws-profile-lifecycle.sh" 'sweep_aws' \
  "wrapper must route destructive sweep calls through the not-found-only tolerant helper"
require_text "scripts/aws-profile-lifecycle.sh" 'revalidate_sweep_target' \
  "wrapper must revalidate exact type and current ownership tags immediately before each deletion"
require_text "scripts/aws-profile-lifecycle.sh" 'sweep_aws elbv2 delete-listener' \
  "wrapper must delete listeners through the tolerant helper"
require_text "scripts/aws-profile-lifecycle.sh" 'sweep_aws elbv2 delete-load-balancer' \
  "wrapper must delete load balancers through the tolerant helper"
require_text "scripts/aws-profile-lifecycle.sh" 'sweep_aws elbv2 delete-target-group' \
  "wrapper must delete target groups through the tolerant helper"
require_text "scripts/aws-profile-lifecycle.sh" 'sweep_aws ec2 delete-security-group' \
  "wrapper must delete security groups through the tolerant helper"
require_text "scripts/aws-profile-lifecycle.sh" 'sweep_aws ec2 delete-volume' \
  "wrapper must delete volumes through the tolerant helper"
require_text "scripts/aws-profile-lifecycle.sh" 'sweep_aws ec2 delete-network-interface' \
  "wrapper must delete network interfaces through the tolerant helper"
require_text "scripts/aws-profile-lifecycle.sh" -- '--output json' \
  "wrapper sweep queries must parse structured JSON and fail closed on malformed output"
require_text "scripts/aws-profile-lifecycle.sh" -- '--resource-arns' \
  "wrapper must read exact ownership tags per load balancer, listener, and target group ARN"
require_text "scripts/aws-profile-lifecycle.sh" 'EVENT sweep delete' \
  "wrapper must emit one ordered event log with each sweep deletion"
require_text "scripts/aws-profile-lifecycle.sh" 'EVENT apply' \
  "wrapper must emit one ordered event log with each root apply"
require_text "scripts/aws-profile-lifecycle.sh" 'No literal client' \
  "wrapper must fail when cluster inputs are absent instead of inventing defaults"
require_text "scripts/aws-profile-lifecycle.sh" 'No literal project' \
  "wrapper must fail when the project input is absent instead of inventing defaults"
require_text "scripts/aws-profile-lifecycle.sh" 'No literal environment' \
  "wrapper must fail when the environment input is absent instead of inventing defaults"
require_text "scripts/aws-profile-lifecycle.sh" 'did not advance' \
  "wrapper must record truthful receipt evidence instead of fabricating a future epoch"
require_text "scripts/aws-profile-lifecycle.sh" 'NotFound' \
  "wrapper must recognize verified not-found states"
require_text "scripts/aws-profile-lifecycle.sh" 'do not match the' \
  "wrapper must bind the receipt cluster set to the profile clusters"
require_text "scripts/aws-profile-lifecycle.sh" 'different volume record' \
  "wrapper must bind the receipt to the exact volume record it was created with"
reject_text "scripts/aws-profile-lifecycle.sh" 'record_epoch + 1' \
  "wrapper must not fabricate a future receipt epoch within the same second"

# The runtime classifier itself is the final durable boundary: protected
# families are not valid sweep target types, regardless of any tags a hostile
# receipt might carry. Route 53 aliases remain Terraform-managed; the sweep
# has no Route 53 target type at all.
sweep_type_function="$(sed -n '/^sweep_target_type() {/,/^}/p' scripts/aws-profile-lifecycle.sh)"
for protected_runtime_id in \
  'arn:aws:acm:us-east-1:575172595729:certificate/example' \
  'route53-record:ZEXAMPLE:_acme-challenge.example.com' \
  'arn:aws:ecr:us-east-1:575172595729:repository/microtodosuite' \
  'arn:aws:secretsmanager:us-east-1:575172595729:secret:microtodosuite/example' \
  'arn:aws:kms:us-east-1:575172595729:key/example' \
  'arn:aws:s3:::microtodosuite-terraform-state' \
  'arn:aws:iam::575172595729:oidc-provider/token.actions.githubusercontent.com'; do
  if bash -c "$sweep_type_function; sweep_target_type \"\$1\"" -- "$protected_runtime_id" >/dev/null 2>&1; then
    fail "protected runtime resource $protected_runtime_id must be unreachable by the sweep"
  fi
done

# Positive inventory: every swept resource carries exact current ownership tags,
# the listener carries its own tag (not its load balancer's trust), the volume
# carries live cluster-scoped tags plus a recorded completed snapshot, and the
# consented volume stays out of the sweep inventory.
[[ "$(jq -r '.clusters[0]' "$quiescence_receipt/receipt.json")" == "lex-mts-eco-eks-main" ]] || \
  fail "quiescence receipt must record the economical cluster set"
[[ "$(jq -r '.inventory.load_balancers[0]' "$quiescence_receipt/receipt.json")" == "arn:aws:elasticloadbalancing:us-east-1:575172595729:loadbalancer/app/k8s-eco-alb/1234567890abcdef" ]] || \
  fail "quiescence receipt must inventory the cluster-owned load balancer"
[[ "$(jq -r '.inventory.listeners[0]' "$quiescence_receipt/receipt.json")" == "arn:aws:elasticloadbalancing:us-east-1:575172595729:listener/app/k8s-eco-alb/1234567890abcdef/9876543210fedcba" ]] || \
  fail "quiescence receipt must inventory the listener behind its own exact cluster tag"
[[ "$(jq -r '.inventory.target_groups[0]' "$quiescence_receipt/receipt.json")" == "arn:aws:elasticloadbalancing:us-east-1:575172595729:targetgroup/k8s-eco-tg/1234567890abcdef" ]] || \
  fail "quiescence receipt must inventory the cluster-owned target group"
[[ "$(jq -c '.inventory.security_groups' "$quiescence_receipt/receipt.json")" == '["sg-0123456789abcdef0"]' ]] || \
  fail "quiescence receipt must inventory the controller security group"
[[ "$(jq -c '.inventory.volumes' "$quiescence_receipt/receipt.json")" == '["vol-0aaa"]' ]] || \
  fail "quiescence receipt must inventory only the snapshotted volume, never the consented one"
[[ "$(jq -c '.inventory.network_interfaces' "$quiescence_receipt/receipt.json")" == '["eni-0123456789abcdef0"]' ]] || \
  fail "quiescence receipt must inventory the orphaned ENI"

# Negative inventory: missing tags, wrong-cluster tags, and malformed tag
# output must keep every resource type out (or fail closed), never sweep it.
sleep 1
in_sandbox env TAG_MODE=wrong-cluster ./scripts/aws-profile-lifecycle.sh quiescence-receipt economical --volume-record "$volume_record" >/dev/null || \
  fail "a receipt over foreign-tagged resources must still be written with an empty inventory"
wrong_cluster_receipt="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'quiescence-economical-2*' | sort | tail -n 1)"
for inventory_key in load_balancers listeners target_groups security_groups volumes network_interfaces; do
  [[ "$(jq -c ".inventory.$inventory_key" "$wrong_cluster_receipt/receipt.json")" == "[]" ]] || \
    fail "wrong-cluster tags must exclude $inventory_key from the receipt inventory"
done
sleep 1
in_sandbox env TAG_MODE=missing ./scripts/aws-profile-lifecycle.sh quiescence-receipt economical --volume-record "$volume_record" >/dev/null || \
  fail "a receipt over untagged resources must still be written with an empty inventory"
missing_tag_receipt="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'quiescence-economical-2*' | sort | tail -n 1)"
for inventory_key in load_balancers listeners target_groups security_groups volumes network_interfaces; do
  [[ "$(jq -c ".inventory.$inventory_key" "$missing_tag_receipt/receipt.json")" == "[]" ]] || \
    fail "missing tags must exclude $inventory_key from the receipt inventory"
done
if in_sandbox env TAG_MODE=malformed ./scripts/aws-profile-lifecycle.sh quiescence-receipt economical --volume-record "$volume_record" >/dev/null 2>&1; then
  fail "malformed tag output must fail the receipt closed instead of sweeping blind"
fi

# Receipt tamper bindings: checksum, profile/account/region/cluster set, and
# the exact volume record the receipt was created with.
tampered_receipt_dir="$volume_sandbox/tampered-receipt"
rm -rf "$tampered_receipt_dir"
cp -r "$quiescence_receipt" "$tampered_receipt_dir"
printf ' ' >>"$tampered_receipt_dir/receipt.json"
if in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$tampered_receipt_dir" --volume-record "$volume_record" >/dev/null 2>&1; then
  fail "a receipt that fails its checksum must be rejected"
fi
rebound_receipt_dir="$volume_sandbox/rebound-receipt"
rm -rf "$rebound_receipt_dir"
cp -r "$quiescence_receipt" "$rebound_receipt_dir"
jq '.clusters = ["lex-mts-ooo-eks-main"]' "$rebound_receipt_dir/receipt.json" >"$rebound_receipt_dir/receipt.json.new"
mv "$rebound_receipt_dir/receipt.json.new" "$rebound_receipt_dir/receipt.json"
(cd "$rebound_receipt_dir" && sha256sum receipt.json >checksums.sha256)
if output="$(in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$rebound_receipt_dir" --volume-record "$volume_record" 2>&1)"; then
  fail "a receipt whose cluster set does not match the profile must be rejected"
fi
grep -q 'do not match the' <<<"$output" || \
  fail "the cluster-set rejection must explain the mismatch"
copied_record_dir="$volume_sandbox/volume-record-copy"
rm -rf "$copied_record_dir"
cp -r "$volume_record" "$copied_record_dir"
if output="$(in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$quiescence_receipt" --volume-record "$copied_record_dir" 2>&1)"; then
  fail "a volume record that is not the receipt's exact record must be rejected"
fi
grep -q 'different volume record' <<<"$output" || \
  fail "the volume-record binding rejection must explain the mismatch"

# One ordered event log: the sweep runs between the workload apply and the
# networking apply, and every sweep deletion is logged between them.
: >"$volume_sandbox/aws.log"
: >"$terraform_log"
apply_output="$(in_sandbox ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)" || \
  fail "apply down rerun must execute successfully"
workload_event_line="$(grep -n 'EVENT apply eco-workload' <<<"$apply_output" | cut -d: -f1 | head -n 1)"
first_sweep_line="$(grep -n 'EVENT sweep delete' <<<"$apply_output" | cut -d: -f1 | head -n 1)"
networking_event_line="$(grep -n 'EVENT apply eco-networking' <<<"$apply_output" | cut -d: -f1 | head -n 1)"
[[ -n "$workload_event_line" && -n "$first_sweep_line" && -n "$networking_event_line" ]] || \
  fail "the apply must log workload applies, sweep deletions, and networking applies in one event log"
[[ "$workload_event_line" -lt "$first_sweep_line" && "$first_sweep_line" -lt "$networking_event_line" ]] || \
  fail "the sweep must run between the workload destruction and the networking apply in the event log"
grep -q 'EVENT sweep delete load-balancer' <<<"$apply_output" || \
  fail "the event log must name the load balancer deletion"
grep -q 'EVENT sweep delete volume' <<<"$apply_output" || \
  fail "the event log must name the volume deletion"

# Snapshot gate: a recorded snapshot that is not completed blocks the volume.
if output="$(in_sandbox env SNAP_STATE=pending ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)"; then
  fail "an incomplete recorded snapshot must block the volume deletion"
fi
grep -qi 'snapshot' <<<"$output" || \
  fail "the snapshot refusal must name the snapshot"

# Gone is success: already-absent resources are skipped, verified not-found
# deletes are tolerated, and the rerun still succeeds.
gone_output="$(in_sandbox env SWEEP_GONE=1 ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)" || \
  fail "an idempotent rerun over already-absent resources must succeed"
grep -qi 'absent\|NotFound' <<<"$gone_output" || \
  fail "the idempotent rerun must report already-absent resources"

# Partial failure is failure, then recovery: a dependency error aborts the
# apply instead of being swallowed, and the rerun completes.
failonce_status=0
output="$(in_sandbox env SWEEP_FAIL_ONCE=1 ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)" || failonce_status=$?
if [[ "$failonce_status" -eq 0 ]]; then
  fail "a dependency failure during the sweep must fail the apply"
fi
grep -q 'vol-0aaa' <<<"$output" || \
  fail "the partial failure must name the volume it failed on"
rm -f "$volume_sandbox/sweep-fail-once.done"
in_sandbox ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" >/dev/null || \
  fail "the rerun after a partial failure must complete"

# Permission errors propagate: an arbitrary denial is never turned into success.
if output="$(in_sandbox env SWEEP_HARD_FAIL=load-balancer ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)"; then
  fail "a permission failure during the sweep must fail the apply"
fi
grep -q 'UnauthorizedOperation' <<<"$output" || \
  fail "the permission failure must propagate its cause"

# Cluster-scoped sweep safety (spec 003 T016 review). The sweep runs in a shared
# account, against a receipt written before the cluster is destroyed, and its
# deletions must leave the networking teardown unblocked. Ownership must name
# the exact cluster, the inventory must not depend on a pre-destroy attachment
# state, ENIs must precede the security groups they hold, and only a verified
# not-found may count as absence.
require_text "scripts/aws-profile-lifecycle.sh" 'describe_for_sweep' \
  "wrapper must revalidate through a describe helper that counts only a verified not-found as absence"
reject_text "scripts/aws-profile-lifecycle.sh" '\.Value == \$cluster or \.Value == "true"' \
  "wrapper must not accept a generic ebs.csi.aws.com/cluster=true value as cluster ownership"

# A generic ownership value names no cluster, so in a shared account it can
# never make a volume sweepable. The exact cluster value and the Kubernetes
# owned tag both must.
sleep 1
in_sandbox env TAG_MODE=generic-volume ./scripts/aws-profile-lifecycle.sh quiescence-receipt economical \
  --volume-record "$volume_record" >/dev/null || \
  fail "a receipt over generically tagged volumes must still be written"
generic_volume_receipt="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'quiescence-economical-2*' | sort | tail -n 1)"
[[ "$(jq -c '.inventory.volumes' "$generic_volume_receipt/receipt.json")" == "[]" ]] || \
  fail "a generic ebs.csi.aws.com/cluster=true value must never make a volume sweepable in a shared account"
sleep 1
in_sandbox env TAG_MODE=k8s-owned-volume ./scripts/aws-profile-lifecycle.sh quiescence-receipt economical \
  --volume-record "$volume_record" >/dev/null || \
  fail "a receipt over Kubernetes-owned volumes must be written"
k8s_owned_receipt="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'quiescence-economical-2*' | sort | tail -n 1)"
[[ "$(jq -c '.inventory.volumes' "$k8s_owned_receipt/receipt.json")" == '["vol-0aaa"]' ]] || \
  fail "a volume tagged kubernetes.io/cluster/<cluster>=owned must stay sweepable"

# The receipt is created before the cluster is destroyed, so an exact-tagged,
# snapshot-recorded volume may still be attached. It must be inventoried, and
# the availability requirement must hold immediately before the delete instead.
sleep 1
in_sandbox env VOL_STATE=in-use ./scripts/aws-profile-lifecycle.sh quiescence-receipt economical \
  --volume-record "$volume_record" >/dev/null || \
  fail "a receipt over an attached PVC volume must still be written"
attached_volume_receipt="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'quiescence-economical-2*' | sort | tail -n 1)"
[[ "$(jq -c '.inventory.volumes' "$attached_volume_receipt/receipt.json")" == '["vol-0aaa"]' ]] || \
  fail "a volume attached when the receipt is written must still be inventoried; the cluster is destroyed after the receipt"
if output="$(in_sandbox env VOL_STATE=in-use ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)"; then
  fail "a volume still attached immediately before its delete must refuse"
fi
grep -q 'vol-0aaa' <<<"$output" || fail "the attached-volume refusal must name the volume"
grep -qi 'available' <<<"$output" || fail "the attached-volume refusal must name the state it requires"

# The same holds for ENIs: in use when the receipt is written is expected, and
# still in use once the load balancers are gone blocks the networking teardown,
# so it must fail closed rather than be called absent or silently deferred.
sleep 1
in_sandbox env ENI_STATUS=in-use ./scripts/aws-profile-lifecycle.sh quiescence-receipt economical \
  --volume-record "$volume_record" >/dev/null || \
  fail "a receipt over an in-use ENI must still be written"
in_use_eni_receipt="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'quiescence-economical-2*' | sort | tail -n 1)"
[[ "$(jq -c '.inventory.network_interfaces' "$in_use_eni_receipt/receipt.json")" == '["eni-0123456789abcdef0"]' ]] || \
  fail "an ENI in use when the receipt is written must still be inventoried; the cluster is destroyed after the receipt"
in_use_eni_status=0
output="$(in_sandbox env ENI_STATUS=in-use ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)" || in_use_eni_status=$?
[[ "$in_use_eni_status" -ne 0 ]] || \
  fail "an ENI still in use after the load balancers are deleted must fail the apply instead of being deferred"
grep -q 'eni-0123456789abcdef0' <<<"$output" || \
  fail "the in-use ENI refusal must name the interface"
if grep -q 'network-interface eni-0123456789abcdef0: already absent' <<<"$output"; then
  fail "a present but in-use ENI must never be reported as already absent"
fi

# An orphaned ENI holds the controller security group, so it must be deleted
# first or the security-group delete fails on a dependency the sweep created.
: >"$volume_sandbox/aws.log"
: >"$terraform_log"
in_sandbox ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" >/dev/null || \
  fail "apply down must succeed before the sweep ordering is checked"
eni_delete_line="$(grep -n 'ec2 delete-network-interface' "$volume_sandbox/aws.log" | cut -d: -f1 | head -n 1)"
security_group_delete_line="$(grep -n 'ec2 delete-security-group' "$volume_sandbox/aws.log" | cut -d: -f1 | head -n 1)"
[[ -n "$eni_delete_line" && -n "$security_group_delete_line" ]] || \
  fail "the sweep must delete both the orphaned ENI and the controller security group"
[[ "$eni_delete_line" -lt "$security_group_delete_line" ]] || \
  fail "orphaned ENIs must be deleted before the controller security groups that they hold"

# Only a verified not-found is absence. A denied or throttled describe during
# revalidation must propagate and fail the apply.
for denied_describe in tags load-balancers listeners target-groups security-groups network-interfaces volumes; do
  denied_status=0
  output="$(in_sandbox env DESCRIBE_DENY="$denied_describe" \
    ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)" || denied_status=$?
  [[ "$denied_status" -ne 0 ]] || \
    fail "a denied describe-$denied_describe during revalidation must fail the apply instead of counting as absence"
  grep -q 'AccessDenied' <<<"$output" || \
    fail "the denied describe-$denied_describe must propagate its cause"
done
throttled_status=0
output="$(in_sandbox env DESCRIBE_THROTTLE=security-groups \
  ./scripts/aws-profile-lifecycle.sh apply economical down "$down_bundle" 2>&1)" || throttled_status=$?
[[ "$throttled_status" -ne 0 ]] || \
  fail "a throttled describe during revalidation must fail the apply instead of counting as absence"
grep -q 'Throttling' <<<"$output" || \
  fail "the throttled describe must propagate its cause"

# An empty inventory applies cleanly and deletes nothing.
fresh_transition
in_sandbox env TAG_MODE=missing ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$missing_tag_receipt" --volume-record "$volume_record" >/dev/null || \
  fail "a down plan over an empty inventory must succeed"
empty_bundle="$(latest_bundle economical down)"
: >"$volume_sandbox/aws.log"
: >"$terraform_log"
in_sandbox ./scripts/aws-profile-lifecycle.sh apply economical down "$empty_bundle" >/dev/null || \
  fail "an apply over an empty sweep inventory must succeed"
if grep -q 'delete-' "$volume_sandbox/aws.log"; then
  fail "an empty sweep inventory must delete nothing"
fi

# Amazon EKS refuses to delete a protected cluster, so a protected cluster first
# gets a bundle that only turns the protection off (FR-024).
fresh_transition
output="$(in_sandbox env CLUSTER_PROTECTION=true ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$quiescence_receipt" --volume-record "$volume_record" 2>&1)" || \
  fail "a down plan against a protected cluster must create the unprotect bundle"
[[ "$(bundle_roots "$(latest_bundle economical down)")" == "eco-workload" ]] || \
  fail "the unprotect bundle must hold only the cluster root"
grep -Eq '^eco/workload plan .*-var=cluster_deletion_protection=false' "$terraform_log" || \
  fail "the unprotect bundle must plan the cluster with deletion protection off"
grep -Eq '^eco/workload plan .*-target=module\.eks_cluster\.aws_eks_cluster\.this' "$terraform_log" || \
  fail "the unprotect bundle must target only the EKS cluster resource"
if grep -Eq 'plan -destroy|^eco/(security-irsa|networking) plan' "$terraform_log"; then
  fail "the unprotect bundle must destroy nothing and plan no other root"
fi
grep -q 'again' <<<"$output" || \
  fail "the unprotect bundle must tell the operator to plan the down transition again"

fresh_transition
subnet_delete='{"resource_changes":[{"address":"module.network.aws_subnet.this[\"priva\"]","type":"aws_subnet","change":{"actions":["delete"]}}]}'
if output="$(in_sandbox env CLUSTER_PROTECTION=false PLAN_JSON="$subnet_delete" ./scripts/aws-profile-lifecycle.sh plan economical down \
  --receipt "$quiescence_receipt" --volume-record "$volume_record" 2>&1)"; then
  fail "a networking down plan that deletes a subnet must be rejected"
fi
grep -Fq 'module.network.aws_subnet.this["priva"]' <<<"$output" || \
  fail "the rejection must name the address beyond the NAT egress"

# Economical up restores the NAT egress and the cluster first. The IRSA pass
# reads the cluster's issuer, so without a cluster it waits for a second bundle
# (FR-022).
fresh_transition
output="$(in_sandbox ./scripts/aws-profile-lifecycle.sh plan economical up 2>&1)" || \
  fail "an up plan without a cluster must create the first bundle"
[[ "$(bundle_roots "$(latest_bundle economical up)")" == "eco-networking eco-workload" ]] || \
  fail "without a cluster, the up bundle must hold eco/networking and eco/workload only"
grep -Eq '^eco/networking plan .*-var=nat_gateways_enabled=true' "$terraform_log" || \
  fail "the up transition must restore the NAT egress"
if grep -Eq 'plan -destroy|^eco/security-irsa plan' "$terraform_log"; then
  fail "the first up bundle must destroy nothing and defer the IRSA pass"
fi
grep -q 'again' <<<"$output" || \
  fail "the first up bundle must tell the operator to plan the up transition again"

fresh_transition
in_sandbox env CLUSTER_PROTECTION=true ./scripts/aws-profile-lifecycle.sh plan economical up >/dev/null || \
  fail "an up plan with a cluster must succeed"
[[ "$(bundle_roots "$(latest_bundle economical up)")" == "eco-networking eco-workload eco-security-irsa" ]] || \
  fail "with a cluster, the up bundle must also plan the IRSA pass"

output="$(in_sandbox env CLUSTER_PROTECTION=true ./scripts/aws-profile-lifecycle.sh status economical)"
if ! grep -Eq '^UP[[:space:]]+eco-workload$' <<<"$output" || ! grep -Eq '^DOWN[[:space:]]+eco-networking$' <<<"$output"; then
  fail "status must report each runtime root from its own state"
fi

# The full profile (FR-027 to FR-029). Up plans the egress hub, then each spoke
# with its transit egress, then each cluster. The spokes read the hub's transit
# gateway at plan time, so while the hub's state holds none, the up bundle holds
# only the hub.
fresh_transition
output="$(in_sandbox ./scripts/aws-profile-lifecycle.sh plan full up 2>&1)" || \
  fail "a full up plan without the hub must create the hub bundle"
[[ "$(bundle_roots "$(latest_bundle full up)")" == "shd-networking" ]] || \
  fail "without the hub, the full up bundle must hold shd/networking only"
if grep -Eq '^f(dev|stg|prd)/[a-z]+ plan ' "$terraform_log"; then
  fail "the hub bundle must plan no spoke and no cluster"
fi
grep -q 'again' <<<"$output" || \
  fail "the hub bundle must tell the operator to plan the up transition again"

fresh_transition
in_sandbox env HUB_PRESENT=1 ./scripts/aws-profile-lifecycle.sh plan full up >/dev/null || \
  fail "a full up plan with the hub must succeed"
[[ "$(bundle_roots "$(latest_bundle full up)")" == "shd-networking fdev-networking fstg-networking fprd-networking fdev-workload fstg-workload fprd-workload" ]] || \
  fail "without a cluster, the full up bundle must plan the hub, the three spokes, and the three clusters, and defer the three IRSA passes"
for environment in fdev fstg fprd; do
  grep -Eq "^${environment}/networking plan .*-var=transit_enabled=true" "$terraform_log" || \
    fail "the full up transition must restore the transit egress of $environment"
done
if grep -Eq 'plan -destroy' "$terraform_log"; then
  fail "the full up bundle must destroy nothing"
fi
if grep -Eq '^f(dev|stg|prd)/security-irsa plan ' "$terraform_log"; then
  fail "the IRSA passes read their cluster's issuer, so they wait for the second up bundle"
fi

fresh_transition
in_sandbox env HUB_PRESENT=1 CLUSTER_PROTECTION=false ./scripts/aws-profile-lifecycle.sh plan full up >/dev/null || \
  fail "a full up plan with the hub and the clusters must succeed"
[[ "$(bundle_roots "$(latest_bundle full up)")" == "shd-networking fdev-networking fstg-networking fprd-networking fdev-workload fstg-workload fprd-workload fdev-security-irsa fstg-security-irsa fprd-security-irsa" ]] || \
  fail "with the clusters, the full up bundle must also plan the three IRSA passes"

# Capacity limit L1 (decision D2 as amended on 2026-09-13). The Region allows five
# VPCs and the two profiles together need all five, so an up transition refuses to
# start while the VPCs the Region holds plus the ones it would create exceed the
# quota. A leftover default VPC would otherwise fail the last spoke after the hub
# and the first spokes already exist.
fresh_transition
output="$(in_sandbox env VPC_COUNT=2 ./scripts/aws-profile-lifecycle.sh plan full up 2>&1)" && \
  fail "a full up plan must refuse when the hub and the three spokes would exceed the VPC quota"
grep -q 'capacity limit L1' <<<"$output" || \
  fail "the VPC quota refusal must name capacity limit L1"
[[ -z "$(latest_bundle full up)" ]] || \
  fail "a refused up transition must save no bundle"
if grep -Eq '^[a-z]+/[a-z-]+ plan ' "$terraform_log"; then
  fail "a refused up transition must plan no root"
fi

fresh_transition
in_sandbox env HUB_PRESENT=1 VPC_COUNT=2 ./scripts/aws-profile-lifecycle.sh plan full up >/dev/null || \
  fail "with the hub's VPC already counted, three spokes beside it and the economical VPC fit the quota of five"

fresh_transition
if in_sandbox env HUB_PRESENT=1 VPC_COUNT=3 ./scripts/aws-profile-lifecycle.sh plan full up >/dev/null 2>&1; then
  fail "with the hub and one VPC outside the platform, three more spokes exceed the quota of five"
fi

fresh_transition
in_sandbox env HUB_PRESENT=1 SPOKES_PRESENT=1 CLUSTER_PROTECTION=false VPC_COUNT=6 ./scripts/aws-profile-lifecycle.sh plan full up >/dev/null || \
  fail "an up transition that creates no VPC must not be held back by the VPC quota"

# Full down destroys the clusters, removes each spoke's transit egress, and
# destroys the hub last, once no attachment remains. The spokes are never
# destroyed: their VPCs hold the security groups of each environment's security
# root.
in_sandbox ./scripts/aws-profile-lifecycle.sh snapshot-volumes full >/dev/null
full_volume_record="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'volumes-full-*' | head -n 1)"
[[ -n "$full_volume_record" ]] || fail "snapshot-volumes must write a full-profile volume record"
in_sandbox ./scripts/aws-profile-lifecycle.sh quiescence-receipt full --volume-record "$full_volume_record" >/dev/null
full_quiescence_receipt="$(find "$sandbox_ops/.aws-profile-plans" -maxdepth 1 -type d -name 'quiescence-full-*' | head -n 1)"
[[ -n "$full_quiescence_receipt" && -f "$full_quiescence_receipt/receipt.json" ]] || \
  fail "quiescence-receipt must write a full-profile receipt.json"
fresh_transition
in_sandbox env HUB_PRESENT=1 CLUSTER_PROTECTION=false ./scripts/aws-profile-lifecycle.sh plan full down \
  --receipt "$full_quiescence_receipt" --volume-record "$full_volume_record" >/dev/null || \
  fail "a full down plan against unprotected clusters must succeed"
[[ "$(bundle_roots "$(latest_bundle full down)")" == "fprd-security-irsa fstg-security-irsa fdev-security-irsa fprd-workload fstg-workload fdev-workload fprd-networking fstg-networking fdev-networking shd-networking" ]] || \
  fail "the full down bundle must destroy the IRSA passes, then the clusters, then remove the spokes' transit egress, then destroy the hub"
for environment in fdev fstg fprd; do
  grep -Eq "^${environment}/security-irsa plan -destroy " "$terraform_log" || \
    fail "the $environment IRSA pass must be planned for destruction"
  grep -Eq "^${environment}/workload plan -destroy " "$terraform_log" || \
    fail "the $environment cluster must be planned for destruction"
  grep -Eq "^${environment}/networking plan .*-var=transit_enabled=false" "$terraform_log" || \
    fail "the $environment spoke must be planned without its transit egress"
done
if grep -Eq '^f(dev|stg|prd)/networking plan -destroy' "$terraform_log"; then
  fail "a spoke must never be destroyed"
fi
grep -Eq '^shd/networking plan -destroy ' "$terraform_log" || \
  fail "the egress hub must be planned for destruction"

fresh_transition
in_sandbox env HUB_PRESENT=1 CLUSTER_PROTECTION=true ./scripts/aws-profile-lifecycle.sh plan full down \
  --receipt "$full_quiescence_receipt" --volume-record "$full_volume_record" >/dev/null || \
  fail "a full down plan against protected clusters must create the unprotect bundle"
[[ "$(bundle_roots "$(latest_bundle full down)")" == "fprd-workload fstg-workload fdev-workload" ]] || \
  fail "the full unprotect bundle must hold only the protected clusters"
for environment in fdev fstg fprd; do
  grep -Eq "^${environment}/workload plan .*-var=cluster_deletion_protection=false" "$terraform_log" || \
    fail "the $environment cluster must be planned with deletion protection off"
done
if grep -Eq 'plan -destroy|networking plan' "$terraform_log"; then
  fail "the full unprotect bundle must destroy nothing and plan no network"
fi

output="$(in_sandbox env HUB_PRESENT=1 ./scripts/aws-profile-lifecycle.sh status full)"
if ! grep -Eq '^UP[[:space:]]+shd-networking$' <<<"$output" || ! grep -Eq '^DOWN[[:space:]]+fdev-workload$' <<<"$output"; then
  fail "status must report the hub and each cluster from its own state"
fi

require_text "aws/environments/eco/networking/variables.tf" 'variable "nat_gateways_enabled"' \
  "eco/networking must expose the NAT egress switch the lifecycle plans"
require_variable_default "aws/environments/eco/networking/variables.tf" nat_gateways_enabled true \
  "the NAT egress of eco/networking must default on"
require_text "aws/environments/eco/networking/locals.tf" 'var\.nat_gateways_enabled' \
  "eco/networking must build its NAT gateways and private egress from the switch"
for environment in eco fdev fstg fprd; do
  require_text "aws/environments/$environment/workload/variables.tf" 'variable "cluster_deletion_protection"' \
    "$environment/workload must expose the cluster's deletion protection"
  require_variable_default "aws/environments/$environment/workload/variables.tf" cluster_deletion_protection true \
    "the deletion protection of the $environment cluster must default on"
  require_text "aws/environments/$environment/workload/main.tf" 'deletion_protection[[:space:]]*=[[:space:]]*var\.cluster_deletion_protection' \
    "$environment/workload must pass its deletion protection to the cluster module"
done
for environment in fdev fstg fprd; do
  require_file "aws/environments/$environment/security-irsa/main.tf"
  require_text "aws/environments/$environment/security-irsa/main.tf" 'iam-oidc-provider\?ref=iam-oidc-provider-v' \
    "$environment/security-irsa must register its cluster's OIDC issuer"
  require_text "aws/environments/$environment/networking/variables.tf" 'variable "transit_enabled"' \
    "$environment/networking must expose the transit egress switch the lifecycle plans"
  require_variable_default "aws/environments/$environment/networking/variables.tf" transit_enabled true \
    "the transit egress of $environment/networking must default on"
  require_text "aws/environments/$environment/networking/locals.tf" 'var\.transit_enabled' \
    "$environment/networking must build its attachment and private egress from the switch"
done

printf 'PASS: AWS profile lifecycle contract\n'
