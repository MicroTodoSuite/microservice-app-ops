# Tasks: AWS Dedicated Demonstration Foundation (002)

- [x] **1. Synchronize and preserve the workspace**
  - [x] Fast-forward `main` to `origin/main` without losing local Terraform work
  - [x] Create an external backup and retain the synchronization stash

- [x] **2. Restore the dev safety gate**
  - [x] Make newly introduced account-level webhook secrets and IAM roles owner/consumer aware
  - [x] Apply only the six reviewed resources introduced by the updated `main`
  - [x] Confirm a refresh-backed `dev` plan is genuinely empty

- [x] **3. Configure the cost-reduced demo topology**
  - [x] Add a backward-compatible `single_nat_gateway` foundation input defaulting to `false`
  - [x] Keep `dev` on one NAT gateway per availability zone
  - [x] Configure `demo-full` with one shared NAT gateway
  - [x] Configure `demo-full` with the account-compatible `m7i-flex.large` bootstrap type
  - [x] Keep `demo-full` in shared-resource consumer mode

- [x] **4. Verify the implementation**
  - [x] Run Terraform formatting, validation, and module contract tests
  - [x] Confirm the final refresh-backed `dev` plan remains 0/0/0
  - [x] Save and inspect the `demo-full` recovery plan before applying it

- [x] **5. Apply and verify `demo-full`**
  - [x] Back up the current remote state externally
  - [x] Apply only the reviewed saved recovery plan
  - [x] Confirm one NAT gateway, two healthy `m7i-flex.large` nodes, and an empty post-apply plan
  - [x] Do not perform GitOps registration or direct Kubernetes mutations
