# Implementation Plan: AWS Dedicated Demonstration Foundation (002)

**Branch**: `agent/full-profile-demo` | **Date**: 2026-08-22 | **Spec**: [spec.md](./spec.md)

## Summary

Provision the isolated `demo-full` VPC and EKS environment while fitting the account's existing five-EIP quota. Extend the shared foundation module with a default-off single-NAT switch, keep `dev` on three zonal NAT gateways, and configure `demo-full` with one NAT gateway plus the account-compatible `m7i-flex.large` bootstrap nodes.

## Proposed Changes

1. **Create Environment Directory Structure**:
   - `aws/environments/demo-full/backend/`
   - `aws/environments/demo-full/foundation/`
   Copy the structural files (`main.tf`, `outputs.tf`, `variables.tf`, `versions.tf`, `providers.tf`, `release-secrets.tf`) from `dev`, but change the environment identifiers from `dev` to `demo-full`.

2. **Configure Remote State**:
   - `aws/environments/demo-full/backend/README.md` (Update references to `demo-full`)
   - The S3 backend key is isolated as `environments/demo-full/foundation/terraform.tfstate` in the existing account backend bucket.
   - Create the necessary `.tfbackend` file templates.

3. **Configure Environment Inputs (`tfvars`)**:
   - Network CIDR: `10.20.0.0/16`.
   - Node capacity: Use `m7i-flex.large` with `capacity_type = "ON_DEMAND"`.
   - NAT topology: Set `single_nat_gateway = true` only for `demo-full`.
   - Environment Name: `demo-full`.

4. **Extend and Reuse the Foundation Module**:
   - Ensure `aws/environments/demo-full/foundation/main.tf` invokes `../../../modules/environment-foundation` exactly as `dev` does.
   - Add a `single_nat_gateway` input defaulting to `false`; map it to the upstream VPC module without changing the `dev` topology.
   - Keep account-level ECR, OIDC, IAM, and webhook-secret resources owned by `dev`; consumer environments resolve them through data sources.

## Constitution Check (v1.3.0)

| Principle | Verdict | How this feature complies |
| --- | --- | --- |
| 1. Environment Isolation | PASS | Uses a dedicated cluster and VPC, fulfilling the full-profile specification. |
| 11. Declarative Platform | PASS | Terraform owns VPC, EKS, IAM, ECR, and foundation. |
| Cost-governed exception | PASS | One demo NAT avoids a quota increase while preserving three AZ subnets and a dedicated cluster. |

## Constraints

- This phase does not include ArgoCD bootstrapping, platform add-ons, or business workloads.
- `dev` must retain three NAT gateways and produce a genuinely empty refresh-backed plan after every module change.
- The demo accepts a single-AZ egress dependency; changing this back to zonal NAT gateways requires an EIP quota of at least six.

## Complexity Tracking

| Risk | Why | Mitigation |
| --- | --- | --- |
| State collision | Using the same backend config as dev | Use a strictly different prefix (`demo-full`) and locking configuration. |
| Shared NAT outage | One NAT becomes the egress dependency for all private subnets | Accept explicitly for this demonstration; retain three subnets and document the reduced availability. |
| Account rejects worker type | Non-Free-Tier instance types cannot launch | Validate and use only `m7i-flex.large`. |
