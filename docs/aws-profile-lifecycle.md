# AWS Profile Lifecycle

This runbook controls the cost-bearing AWS runtime while preserving durable Terraform-managed assets. The repository-root Makefile is the primary operator interface and delegates to the lifecycle wrapper, which remains the single implementation of profile ordering, saved plans, and safety gates. Neither layer changes Kubernetes resources directly: environment activation and quiescence remain GitOps changes reconciled by ArgoCD.

## Resource boundary

| Preserved when down | Removed when down |
| --- | --- |
| S3/KMS Terraform backend | Environment VPC and subnets |
| ECR repositories and images | NAT gateways, Elastic IPs, routes, and flow logs |
| Secrets Manager containers and values | EKS control plane and managed node groups |
| Route 53 hosted zones and records | EKS add-ons and cluster-scoped IAM/IRSA roles |
| GitHub Actions OIDC and publication roles | Karpenter queue, key, identities, and event rules |

Durable services can still have small storage, request, hosted-zone, or key charges. `down` removes the dominant runtime spend; it does not promise a zero-dollar account.

## AWS login

The configured Terraform role uses `microtodosuite-login-source`, whose credentials come from the AWS CLI `default` login session. Renew that source, then select the role:

```bash
aws login --profile default --remote
export AWS_PROFILE=microtodosuite-terraform-new
aws sts get-caller-identity
```

The account in the last command must match every selected root's local `expected_account_id`. Never paste console passwords, authorization blocks, access keys, or session tokens into repository files.

## Preflight and status

```bash
export AWS_PROFILE=microtodosuite-terraform-new
make check PROFILE=economical
make init PROFILE=economical
make status PROFILE=economical
```

Every profile-sensitive target requires an explicit `PROFILE=economical|full`; there is no implicit default. Full-profile preflight intentionally stops while its gitignored input files are absent or still target a retired account. Do not copy an old account ID or invent transit-gateway, policy, or operator-CIDR values merely to make preflight green; complete the separately reviewed spec 009 account migration first.

## Start a profile

Commit all infrastructure changes first. Create a saved plan, inspect it, and apply that exact bundle:

```bash
make plan-up PROFILE=economical
make inspect BUNDLE=.aws-profile-plans/economical-up-YYYYMMDDTHHMMSSZ
make apply-up PROFILE=economical BUNDLE=.aws-profile-plans/economical-up-YYYYMMDDTHHMMSSZ
```

After Terraform recreates the runtime, bootstrap or reactivate it only through the repository's reviewed GitOps process. Do not use `kubectl apply` for workload or platform state.

## Stop a profile

Before planning shutdown:

1. Snapshot every PersistentVolume while the workloads still run: `make snapshot-volumes PROFILE=economical`.
   - It finds every EBS volume that the EBS CSI driver created in the profile's region, through the EC2 API.
   - It snapshots each one and waits for the snapshots to complete.
   - It writes a checksummed record under `.aws-profile-plans/volumes-economical-YYYYMMDDTHHMMSSZ/`.
   - A volume whose data may be lost is named with `CONSENT="vol-..."`; the record keeps that consent instead of a snapshot.
2. Only then commit a GitOps change that quiesces the selected environment without deleting durable AWS assets. Quiescence prunes the PersistentVolumeClaims. With the `Delete` reclaim policy, the driver then deletes their volumes, as it did to four observability volumes on 2026-09-11.
3. Merge the change, wait for ArgoCD reconciliation, and record the merged commit SHA.
4. Create and inspect the shutdown bundle. The wrapper rejects:
   - a volume record created after the quiescence commit;
   - a record that misses a volume still present;
   - a record whose snapshots are not complete;
   - any planned deletion of ECR, Secrets Manager, Route 53, GitHub OIDC, or publication identities.

Recreating an EKS cluster restores no data by itself. Restoring a volume from its snapshot is a separate, reviewed GitOps change; the lifecycle does not restore data.

```bash
make snapshot-volumes PROFILE=economical
make plan-down PROFILE=economical GITOPS_REVISION=GITOPS_COMMIT_SHA VOLUME_RECORD=.aws-profile-plans/volumes-economical-YYYYMMDDTHHMMSSZ
make inspect BUNDLE=.aws-profile-plans/economical-down-YYYYMMDDTHHMMSSZ
make apply-down PROFILE=economical BUNDLE=.aws-profile-plans/economical-down-YYYYMMDDTHHMMSSZ
```

`BUNDLE` may be relative to the current directory or absolute. The wrapper
resolves it to a canonical absolute directory before Terraform changes to a
root with `-chdir`, so inspection and apply read the same checksummed plan.

Every apply first writes an external state backup under `~/backups-microtodosuite/`. A genuinely empty state gets a timestamped `no-prior-state` receipt instead.

## Full profile

The full profile uses dependency-safe ordering:

- Up: shared egress, full-dev, demo-full (full staging), full-prod.
- Down: full-prod, demo-full, full-dev, shared egress.

Use the same commands with `PROFILE=full` only after `make check PROFILE=full` passes:

```bash
make check PROFILE=full
make plan-up PROFILE=full
make inspect BUNDLE=.aws-profile-plans/full-up-YYYYMMDDTHHMMSSZ
make apply-up PROFILE=full BUNDLE=.aws-profile-plans/full-up-YYYYMMDDTHHMMSSZ

make snapshot-volumes PROFILE=full
make plan-down PROFILE=full GITOPS_REVISION=GITOPS_COMMIT_SHA VOLUME_RECORD=.aws-profile-plans/volumes-full-YYYYMMDDTHHMMSSZ
make inspect BUNDLE=.aws-profile-plans/full-down-YYYYMMDDTHHMMSSZ
make apply-down PROFILE=full BUNDLE=.aws-profile-plans/full-down-YYYYMMDDTHHMMSSZ
```

On a first full-profile creation, the shared egress transit gateway must exist before a foundation plan can bind to its real ID. When the egress state is empty, `make plan-up PROFILE=full` intentionally creates an egress-only bundle. Apply that reviewed bundle, place its `transit_gateway_id` output in the gitignored full foundation inputs, and run `make plan-up PROFILE=full` again. The second bundle compares those inputs with the live egress output before planning the foundations. Never apply a saved foundation plan containing an obsolete transit gateway ID.

## Required local files

The wrapper refuses to guess missing values. Each root needs its real gitignored backend and variable file:

| Root | Backend | Variables |
| --- | --- | --- |
| dev | `dev.s3.tfbackend` | `dev.tfvars` |
| shared egress | `egress.s3.tfbackend` | `egress.tfvars` |
| full-dev | `full-dev.s3.tfbackend` | `full-dev.tfvars` |
| demo-full | `demo-full.s3.tfbackend` | `demo-full.tfvars` |
| full-prod | `full-prod.s3.tfbackend` | `full-prod.tfvars` |

Every variable file must contain a literal `expected_account_id`. Full-profile migration must also supply the reviewed controller policy ARN, four operator `/32` CIDRs, and the current transit gateway ID where the root requires them.

## Local tool installation

The operator interface requires GNU Make. Its lifecycle wrapper requires the repository-pinned Terraform `1.15.8`, AWS CLI v2, Git, jq, GNU grep, and `sha256sum`. Ripgrep is optional and is not used by the operator lifecycle commands.

The broader full-profile workflow additionally uses kubectl, GitHub CLI, Docker, Azure CLI, and the pinned tools below. Downloaded versions and checksums come from `microservice-app-gitops/scripts/managed/full-profile-toolchain.lock`.

Install the base packages and ShellCheck:

```bash
sudo apt-get update
sudo apt-get install --yes ca-certificates coreutils curl git grep gzip jq make shellcheck tar
```

ripgrep is optional; install it only for interactive repository searches or other development tasks:

```bash
sudo apt-get install --yes ripgrep
```

Install the pinned lifecycle, validation, and supply-chain binaries:

```bash
tool_tmp="$(mktemp -d)"
trap 'rm -rf "$tool_tmp"' EXIT

download_and_verify() {
  url=$1
  sha=$2
  destination=$3
  curl --fail --location --output "$destination" "$url"
  printf '%s  %s\n' "$sha" "$destination" | sha256sum --check
}

mkdir -p "$tool_tmp"/{kustomize,kubeconform,infracost,trivy,syft,crane,oras,cosign}

download_and_verify \
  https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v5.8.1/kustomize_v5.8.1_linux_amd64.tar.gz \
  029a7f0f4e1932c52a0476cf02a0fd855c0bb85694b82c338fc648dcb53a819d \
  "$tool_tmp/kustomize/archive.tar.gz"
tar -xzf "$tool_tmp/kustomize/archive.tar.gz" -C "$tool_tmp/kustomize"
sudo install -m 0755 "$tool_tmp/kustomize/kustomize" /usr/local/bin/kustomize

download_and_verify \
  https://github.com/yannh/kubeconform/releases/download/v0.7.0/kubeconform-linux-amd64.tar.gz \
  c31518ddd122663b3f3aa874cfe8178cb0988de944f29c74a0b9260920d115d3 \
  "$tool_tmp/kubeconform/archive.tar.gz"
tar -xzf "$tool_tmp/kubeconform/archive.tar.gz" -C "$tool_tmp/kubeconform"
sudo install -m 0755 "$tool_tmp/kubeconform/kubeconform" /usr/local/bin/kubeconform

download_and_verify \
  https://github.com/infracost/infracost/releases/download/v0.10.45/infracost-linux-amd64.tar.gz \
  e2f527d8391a87ac00bfc55237ff875107861715e234bbbeb9b6015aba576c77 \
  "$tool_tmp/infracost/archive.tar.gz"
tar -xzf "$tool_tmp/infracost/archive.tar.gz" -C "$tool_tmp/infracost"
sudo install -m 0755 "$tool_tmp/infracost/infracost-linux-amd64" /usr/local/bin/infracost

download_and_verify \
  https://github.com/aquasecurity/trivy/releases/download/v0.74.0/trivy_0.74.0_Linux-64bit.tar.gz \
  2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a \
  "$tool_tmp/trivy/archive.tar.gz"
tar -xzf "$tool_tmp/trivy/archive.tar.gz" -C "$tool_tmp/trivy"
sudo install -m 0755 "$tool_tmp/trivy/trivy" /usr/local/bin/trivy

download_and_verify \
  https://github.com/sigstore/cosign/releases/download/v3.1.3/cosign-linux-amd64 \
  4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71 \
  "$tool_tmp/cosign/cosign"
sudo install -m 0755 "$tool_tmp/cosign/cosign" /usr/local/bin/cosign

download_and_verify \
  https://github.com/anchore/syft/releases/download/v1.51.0/syft_1.51.0_linux_amd64.tar.gz \
  2a2e837a2c8d59ec9af5472ee22d3b04ee463c4e44476ecf993fd1e5ab6ebc7f \
  "$tool_tmp/syft/archive.tar.gz"
tar -xzf "$tool_tmp/syft/archive.tar.gz" -C "$tool_tmp/syft"
sudo install -m 0755 "$tool_tmp/syft/syft" /usr/local/bin/syft

download_and_verify \
  https://github.com/google/go-containerregistry/releases/download/v0.21.9/go-containerregistry_Linux_x86_64.tar.gz \
  5c16d8ddb971cb1d5e6ed8b1e743da8224414eeba2c2762d8f1a61b2f095699e \
  "$tool_tmp/crane/archive.tar.gz"
tar -xzf "$tool_tmp/crane/archive.tar.gz" -C "$tool_tmp/crane"
sudo install -m 0755 "$tool_tmp/crane/crane" /usr/local/bin/crane

download_and_verify \
  https://github.com/oras-project/oras/releases/download/v1.3.3/oras_1.3.3_linux_amd64.tar.gz \
  9ce999f8d2de03fc03968b29d743077a58783e545e5eaa53917ca177352d0e59 \
  "$tool_tmp/oras/archive.tar.gz"
tar -xzf "$tool_tmp/oras/archive.tar.gz" -C "$tool_tmp/oras"
sudo install -m 0755 "$tool_tmp/oras/oras" /usr/local/bin/oras
```

Infracost needs its own API authentication before cost estimates:

```bash
infracost auth login
```

Verify the resulting toolchain:

```bash
terraform version
aws --version
kubectl version --client
kustomize version
kubeconform -v
infracost --version
trivy --version
cosign version
syft version
crane version
oras version
shellcheck --version
```
