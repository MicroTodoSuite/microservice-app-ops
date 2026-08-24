# Tasks: AWS Full-Profile Demonstration Foundation (002)

- [ ] **1. Setup Directory Structure**
  - [ ] Create `aws/environments/demo-full/backend`
  - [ ] Create `aws/environments/demo-full/foundation`

- [ ] **2. Configure State Backend**
  - [ ] Copy `dev` backend template files to `demo-full/backend`
  - [ ] Update backend `README.md` for `demo-full`
  - [ ] Create `demo-full.s3.tfbackend.example` with `demo-full` prefix and lock configuration

- [ ] **3. Configure Foundation Terraform**
  - [ ] Copy `main.tf`, `outputs.tf`, `variables.tf`, `versions.tf`, `providers.tf`, `release-secrets.tf` from `dev/foundation` to `demo-full/foundation`
  - [ ] Ensure `main.tf` invokes `../../../modules/environment-foundation` correctly
  - [ ] Update any hardcoded references to `dev` in descriptions or defaults

- [ ] **4. Configure Environment Variables (`tfvars`)**
  - [ ] Create `demo-full.tfvars.example`
  - [ ] Set `environment_name = "demo-full"`
  - [ ] Set `vpc_cidr = "10.20.0.0/16"`
  - [ ] Set `node_group_capacity_type = "ON_DEMAND"` (or equivalent variable for the full-profile)

- [ ] **5. Verification**
  - [ ] Run `terraform init -backend=false`
  - [ ] Run `terraform validate`
  - [ ] Confirm no modifications were made to `aws/modules/environment-foundation`
