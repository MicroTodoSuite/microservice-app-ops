# Implementation Plan: AWS Full-Profile Demonstration Foundation (002)

**Branch**: `agent/full-profile-demo` | **Date**: 2026-08-22 | **Spec**: [spec.md](./spec.md)

## Summary

Provision an isolated, dedicated AWS environment named `demo-full` to demonstrate the full architecture profile. This environment will reuse the existing Terraform module found in `aws/modules/environment-foundation` unchanged. Only the environment directory, `demo-full`, its backend configuration, and `tfvars` inputs will differ from `dev`.

## Proposed Changes

1. **Create Environment Directory Structure**:
   - `aws/environments/demo-full/backend/`
   - `aws/environments/demo-full/foundation/`
   Copy the structural files (`main.tf`, `outputs.tf`, `variables.tf`, `versions.tf`, `providers.tf`, `release-secrets.tf`) from `dev`, but change the environment identifiers from `dev` to `demo-full`.

2. **Configure Remote State**:
   - `aws/environments/demo-full/backend/README.md` (Update references to `demo-full`)
   - The S3 backend key will be isolated (e.g. `microtodosuite/demo-full/foundation/terraform.tfstate`).
   - Create the necessary `.tfbackend` file templates.

3. **Configure Environment Inputs (`tfvars`)**:
   - Network CIDR: `10.20.0.0/16`.
   - Node capacity mix: Ensure `capacity_type = "ON_DEMAND"` for the worker nodes to reflect the full/expensive architecture.
   - Environment Name: `demo-full`.

4. **Verify Reuse of Foundation Module**:
   - Ensure `aws/environments/demo-full/foundation/main.tf` invokes `../../../modules/environment-foundation` exactly as `dev` does.
   - The VPC, EKS, Node Groups, ECR, and IRSA resources will be created matching the module's logic.

## Constitution Check (v1.3.0)

| Principle | Verdict | How this feature complies |
| --- | --- | --- |
| 1. Environment Isolation | PASS | Uses a dedicated cluster and VPC, fulfilling the full-profile specification. |
| 11. Declarative Platform | PASS | Terraform owns VPC, EKS, IAM, ECR, and foundation. |

## Constraints

- This phase does not include ArgoCD bootstrapping, platform add-ons, or business workloads.
- The foundation module must remain untouched.

## Complexity Tracking

| Risk | Why | Mitigation |
| --- | --- | --- |
| State collision | Using the same backend config as dev | Use a strictly different prefix (`demo-full`) and locking configuration. |
