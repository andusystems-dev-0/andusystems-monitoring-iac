# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- Bumped Alloy resource limits to resolve OOMKilled pod restarts

### Changed
- Updated Grafana values to fix Keycloak login issues
- Configured Grafana to auto-redirect to Keycloak login
- Integrated Keycloak OIDC authentication for Grafana

## [2026-03-23]

### Fixed
- Corrected Grafana datasource load balancer IPs for remote clusters
- Various fixes for the LGTM stack configuration

### Changed
- Added `installCRDs` to Traefik values
- Miscellaneous configuration fixes

## [2026-03-17]

### Added
- Ansible-driven deployment of full LGTM stack (Loki, Grafana, Tempo, Metrics)
- Grafana datasources for local and remote clusters
- Grafana dashboards configuration

### Changed
- Removed per-cluster MinIO deployment in favor of centralized MinIO on the storage cluster

## [2026-03-15]

### Added
- MetalLB load balancer integration for the monitoring cluster
- Grafana Helm values configuration

## [2026-03-14]

### Changed
- Updated Homepage values with new services and correct formatting
- Fixed Keycloak link on Homepage
- Updated Homepage widget sizing
- Added networking repository link to Homepage

## [2026-03-10]

### Added
- Initial full deployment commit with all cluster configurations

## [2026-03-09]

### Fixed
- ArgoCD values file corrections and labeling
- Homepage link behavior (open in new tab)

### Changed
- Updated Homepage values and ArgoCD icon

## [2026-03-08]

### Added
- Longhorn storage deployment for the monitoring cluster
- Proxmox credentials integration for Homepage widget

### Changed
- Updated Homepage configuration with correct service entries
- Updated application values for Longhorn storage integration

## [2026-03-07]

### Added
- Grafana deployment with Helm chart and IngressRoute
- Loki and Grafana values configuration

### Changed
- Homepage values updates for service links

## [2026-03-06]

### Added
- Cert-Manager with Cloudflare DNS01 validation and Let's Encrypt
- Pangolin-Newt VPN client integration
- Repository README with infrastructure overview

### Changed
- Refactored monolithic Ansible role into modular per-component roles
- Reorganized ArgoCD and Cert-Manager roles for better separation
- Cleaned up sensitive information for open-sourcing

### Fixed
- Homepage manifest to use correct ClusterIssuer
- Pangolin manifest configuration

## [2026-03-05]

### Added
- Traefik ingress controller with CRD-based IngressRoutes
- Homepage dashboard with Traefik IngressRoute and TLS
- MetalLB with L2 advertisement mode

### Changed
- Moved Homepage configuration from ConfigMap to inline Helm values
- Traefik RBAC updates for cluster-wide access

## [2026-03-04]

### Added
- Homepage application manifest for ArgoCD deployment
- Error handling for Terraform apply operations

### Changed
- Updated ArgoCD Helm release timeout settings
- Reorganized files for improved readability

## [2026-03-03]

### Changed
- ArgoCD application configuration updates
- Terraform apply error handling improvements

## [2026-03-02]

### Changed
- Removed auto-generated ArgoCD manifest code
- Explored ArgoCD hub-spoke architecture design

## [2026-03-01]

### Fixed
- Terraform VM creation bug fixes
- Updated default cluster name configuration

## [2026-02-26]

### Added
- Homepage deployed via ArgoCD

### Changed
- Minor configuration fixes

## [2026-02-25]

### Added
- Kubernetes cluster setup with kubeadm
- MetalLB and ArgoCD Helm chart installations

## [2026-02-24]

### Added
- Initial repository commit with project structure and README
