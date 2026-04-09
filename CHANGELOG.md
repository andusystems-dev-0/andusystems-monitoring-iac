# Changelog

All notable changes to the andusystems-monitoring project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed
- Bumped Alloy resource limits to resolve OOMKilled pod evictions

### Changed
- Updated Grafana values to fix login issues with Keycloak OIDC
- Configured Grafana to auto-redirect to Keycloak login
- Added installCRDs to monitoring Traefik values
- Fixed Grafana datasource load balancer IPs for networking cluster

## [0.5.0] - 2026-03-17

### Added
- Full LGTM stack deployment via Ansible (Loki, Grafana, Tempo, Alloy)
- Ansible roles for kube-prometheus-stack, Loki, Tempo, Alloy, and Grafana
- Grafana datasources for multi-cluster observability (Management, Networking, Storage, FleetDock)
- Grafana dashboards (node-exporter-full)
- MetalLB deployment for monitoring cluster

### Changed
- Removed local MinIO deployment in favor of centralized MinIO on storage cluster
- Updated Grafana values with dashboard provisioning and datasource configuration

## [0.4.0] - 2026-03-14

### Added
- New services added to Homepage (expanded service catalog)
- Networking repository bookmark added to Homepage

### Changed
- Updated Homepage values with correct formatting and widget sizing
- Updated Pi-hole Homepage link to use DNS name
- Fixed Keycloak link on Homepage
- Updated GitHub bookmarks to reflect correct VLAN naming
- Removed Prometheus and Loki entries from Homepage monitoring services section

## [0.3.0] - 2026-03-08

### Added
- Longhorn distributed storage deployment for the monitoring cluster
- Proxmox credentials added to Ansible vault

### Fixed
- Fixed path references in ArgoCD deployment script
- Updated application values for Longhorn storage integration

## [0.2.0] - 2026-03-06

### Added
- Cert-Manager with Let's Encrypt DNS-01 validation via CloudFlare
- Pangolin Newt tunnel agent integration
- Grafana deployment with IngressRoute and TLS
- Traefik ingress controller with IngressRoute CRD support
- Homepage dashboard with IngressRoute configuration
- Ansible Vault for secrets management
- README with VLAN architecture overview

### Changed
- Refactored Ansible roles from monolithic structure to modular per-component roles
- Reorganized ArgoCD and Cert-Manager roles
- Committed changes to hide sensitive information for open-sourcing
- Homepage configuration moved from ConfigMap to inline Helm values

### Removed
- Deprecated cert-manager code and old manifest files
- ArgoCD manifest (using management repo instance instead)
- Traefik dashboard IngressRoute (not needed)

## [0.1.0] - 2026-02-25

### Added
- Initial repository setup
- Kubernetes cluster provisioning via kubeadm with Flannel CNI
- MetalLB load balancer installation
- ArgoCD Helm chart deployment
- Homepage deployment via ArgoCD
- Terraform configuration for Proxmox VM creation
- Basic Ansible playbook structure

### Changed
- Updated Terraform configuration for VM creation bug fixes
- Adjusted default cluster name
