# AWS Profile Lifecycle

This runbook controls the cost-bearing AWS runtime while preserving the persistent Terraform-managed assets. The repository-root Makefile is the primary operator interface and delegates to the lifecycle wrapper, which remains the single implementation of profile ordering, saved plans, and safety gates. Neither layer changes Kubernetes resources directly: environment activation and quiescence remain GitOps changes reconciled by ArgoCD.

## Resource boundary

The economical profile operates the rebuilt `eco` roots (ops spec 004). The lifecycle never plans a persistent root.

| Root | Class | When the profile is down |
| --- | --- | --- |
| `shd/state` | Persistent | The S3 state bucket and its KMS key remain. |
| `shd/security` | Persistent | The GitHub OIDC provider, the image publisher and Terraform deploy roles, and the flow-log key and role remain. |
| `shd/registry` | Persistent | The ECR repositories and their images remain. |
| `shd/dns` | Persistent | The public hosted zone and its records remain. |
| `eco/security` | Persistent | The cluster, node, and add-on roles, the EKS keys, the security groups, and the JWT and webhook secrets remain. |
| `eco/networking` | Persistent, with runtime egress | The VPC, subnets, route tables, internet gateway, and flow log remain. The NAT gateways, their Elastic IPs, and the private default routes are removed. |
| `eco/workload` | Runtime | The cluster, its add-ons and access entries, the bootstrap node group, and the control-plane log group are destroyed. |
| `eco/security-irsa` | Runtime | The cluster's OIDC provider and the IRSA roles are destroyed. |

`eco/networking` is never destroyed, because `eco/security`'s security groups belong to its VPC. Its NAT gateways and their public IPv4 addresses are charged by the hour, so they go down with the cluster.

Persistent services still charge for storage, keys, secrets, and the hosted zone. `down` removes the dominant runtime spend; it does not promise a zero-dollar account.

## AWS login

The configured Terraform role uses `microtodosuite-login-source`, whose credentials come from the AWS CLI `default` login session. Renew that source, then select the role:

```bash
aws login --profile default --remote
export AWS_PROFILE=microtodosuite-terraform-new
aws sts get-caller-identity
```

The account in the last command must equal `AWS_ACCOUNT_ID` in `config/aws-account.env` and every selected root's `aws_account_id`. Never paste console passwords, authorization blocks, access keys, or session tokens into repository files.

## Preflight and status

```bash
export AWS_PROFILE=microtodosuite-terraform-new
make check PROFILE=economical
make init PROFILE=economical
make status PROFILE=economical
```

Every profile-sensitive target requires an explicit `PROFILE=economical|full`; there is no implicit default. `status` reports each runtime root as `UP` while its state holds what `down` removes: the NAT gateways, the cluster, or the IRSA roles.

## Start a profile

Commit all infrastructure changes first. Create a saved plan, inspect it, and apply that exact bundle:

```bash
make plan-up PROFILE=economical
make inspect BUNDLE=.aws-profile-plans/economical-up-YYYYMMDDTHHMMSSZ
make apply-up PROFILE=economical BUNDLE=.aws-profile-plans/economical-up-YYYYMMDDTHHMMSSZ
```

The bundle plans `eco/networking` with its NAT gateways, then `eco/workload`, then `eco/security-irsa`.

**While no cluster exists, up takes two bundles.** The IRSA pass reads the cluster's OIDC issuer, so the first bundle holds only `eco/networking` and `eco/workload`, and `inspect` shows `Pass: cluster-first`. Apply it, then run `make plan-up PROFILE=economical` again. The second bundle adds the IRSA pass; the first two roots should plan no changes.

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
   - any planned deletion of ECR, Secrets Manager, Route 53, GitHub OIDC, or publication identities;
   - an `eco/networking` plan that deletes anything but the NAT gateways, their Elastic IPs, and the private NAT routes.

Recreating an EKS cluster restores no data by itself. Restoring a volume from its snapshot is a separate, reviewed GitOps change; the lifecycle does not restore data.

```bash
make snapshot-volumes PROFILE=economical
make plan-down PROFILE=economical GITOPS_REVISION=GITOPS_COMMIT_SHA VOLUME_RECORD=.aws-profile-plans/volumes-economical-YYYYMMDDTHHMMSSZ
make inspect BUNDLE=.aws-profile-plans/economical-down-YYYYMMDDTHHMMSSZ
make apply-down PROFILE=economical BUNDLE=.aws-profile-plans/economical-down-YYYYMMDDTHHMMSSZ
```

The bundle destroys `eco/security-irsa`, then `eco/workload`, and plans `eco/networking` without its NAT gateways.

**A protected cluster takes two bundles.** Amazon EKS refuses to delete a cluster whose deletion protection is on, and `eco/workload` keeps it on by default.
- While the protection is on, the bundle holds only an `eco/workload` plan that turns it off, and `inspect` shows `Pass: unprotect`. The wrapper rejects that plan if it deletes anything.
- Apply it, then run the same `make plan-down PROFILE=economical` command again, with the same `GITOPS_REVISION` and `VOLUME_RECORD`. That second bundle is the destroy bundle.
- The two cannot share a bundle: applying the first changes `eco/workload`'s state, and Terraform refuses a saved plan whose state has changed.
- If the teardown is abandoned after the first bundle, the next plan of `eco/workload` turns the protection back on.

`BUNDLE` may be relative to the current directory or absolute. The wrapper
resolves it to a canonical absolute directory before Terraform changes to a
root with `-chdir`, so inspection and apply read the same checksummed plan.

Every apply first writes an external state backup under `~/backups-microtodosuite/`. A genuinely empty state gets a timestamped `no-prior-state` receipt instead.

## Full profile

The full profile will operate `shd/networking` and the `fdev`, `fstg`, and `fprd` roots, which ops spec 004 T012 writes. Until their records join the wrapper, every full-profile command that reads state stops and names that task. Use the same commands with `PROFILE=full` only after `make check PROFILE=full` passes.

## Legacy roots

The wrapper no longer plans the legacy roots:
- `aws/environments/dev/foundation`, whose state still holds the persistent resources under their old names until ops spec 004 moves and deletes them;
- `aws/shared/egress` and the `full-dev`, `demo-full`, and `full-prod` foundations, whose inputs target a retired account.

Release `v1.17.0` is the last whose wrapper maps them. Operate a legacy root, if ever needed, from a separate worktree at that tag.

## Required local files

The wrapper refuses to guess missing values. Each root needs its real gitignored backend and variable file, copied from the committed `.example` beside it:

| Root | Backend | Variables |
| --- | --- | --- |
| `aws/environments/eco/networking` | `networking.s3.tfbackend` | `eco.tfvars` |
| `aws/environments/eco/workload` | `workload.s3.tfbackend` | `eco.tfvars` |
| `aws/environments/eco/security-irsa` | `security-irsa.s3.tfbackend` | `eco.tfvars` |

Every variable file sets a literal `aws_account_id`, equal to `AWS_ACCOUNT_ID` in `config/aws-account.env`, and a literal `aws_region`. All roots of a profile use one region.

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
