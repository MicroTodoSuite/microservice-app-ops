# Changelog

All notable changes to this module are documented here, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

## [Unreleased]

### Added

- The Azure disaster-recovery foundation (gitops specs/009-full-platform-rollout
  T125): AKS 1.35 on Azure CNI Overlay with Cilium in a private node subnet,
  Entra ID RBAC with named administrators, pre-created cluster and kubelet
  identities with narrowly scoped role assignments, an empty RBAC-only Key
  Vault closed by default with exact reader and seed boundaries, a registry,
  encrypted recovery storage, and a Terraform-owned static ingress public IP in
  a dedicated resource group.
