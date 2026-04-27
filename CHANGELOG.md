# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [2025-04-26]

### Added
- `apps/cluster-status/manifest.yml` — lightweight nginx health-check endpoint exposed via
  Traefik, used by ArgoCD and Homepage portfolio to probe cluster availability.

### Changed
- Bumped Alloy resource limits (CPU and memory) across all four sub-charts to prevent
  OOMKilled restarts under load.
- Updated Grafana Helm values to resolve login issues; temporarily adjusted OAuth settings
  while Keycloak OIDC configuration was stabilised.
- Updated Grafana Helm values to auto-redirect users to the Keycloak login page instead of
  showing the Grafana native login form.
- Updated Grafana Helm values for full Keycloak OIDC integration including role mapping.
- Fixed Grafana Helm values to use the correct LoadBalancer IPs for the networking cluster
  datasources.
- Updated Grafana datasource URLs and dashboard configuration (node-exporter-full gnetId
  1860); removed dedicated MinIO deployment in favour of a centralised MinIO instance.
- Iterative fixes to Loki, Tempo, Alloy, and Grafana stack deployment issues.

### Added (earlier 2025)
- Full Ansible deployment of the LGTM stack (Grafana, Loki, Tempo, Alloy) via roles and
  Helm values files.
- Pushed initial Grafana values files and ArgoCD-based deployment wiring.
- Added MetalLB to the monitoring cluster (Terraform layer-2 module + Ansible role).
- Iterative Homepage dashboard updates: services, bookmarks, widgets, link targets.
- Added `installCRDs` to the monitoring cluster Traefik values.

## [2025-03-14]

### Added
- Initial comprehensive commit: Kubernetes cluster bootstrap (kubeadm, Flannel CNI),
  Ansible roles for all components, Terraform integration for VM provisioning.
- Homepage dashboard with infrastructure, networking, security, monitoring, and CI/CD
  service groups.
- cert-manager with Let's Encrypt DNS-01 via Cloudflare.
- Pangolin/Newt VPN client deployment.
- kube-prometheus-stack, Loki, Tempo, and Alloy initial configuration.
- Grafana with multi-cluster datasources (management, storage, networking, fleetdock).
- Ansible inventory and vault structure.
- `.gitignore` and `.gitattributes` baseline.
