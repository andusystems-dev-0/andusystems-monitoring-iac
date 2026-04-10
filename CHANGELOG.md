# Changelog

All notable changes to the andusystems-monitoring repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2026-04-05]

### Fixed
- Bumped Alloy resource limits to resolve OOMKilled crashes

## [2026-03-23]

### Fixed
- Grafana values updated to fix Keycloak login issues
- Grafana values updated to auto-redirect to Keycloak login
- Grafana values configured for Keycloak SSO integration
- Various small fixes across configurations
- Added `installCRDs` to monitoring Traefik values
- Fixed Grafana datasource load balancer IPs for networking cluster

## [2026-03-17]

### Added
- Ansible deployment roles for LGTM stack (Loki, Grafana, Tempo, Metrics)
- Grafana dashboards and datasource configurations
- Centralized MinIO for Loki/Tempo object storage (removed per-cluster MinIO deployment)

### Fixed
- Grafana values corrected for load balancer IPs on datasources
- Various fixes for LGTM stack integration issues

## [2026-03-15]

### Added
- Grafana Helm values files
- MetalLB deployment to monitoring cluster

## [2026-03-14]

### Added
- Homepage service entries for networking repository
- New services added to Homepage dashboard

### Changed
- Full deployment commit for monitoring cluster (2026-03-14)

### Fixed
- Homepage values formatting corrections
- Homepage widget sizing
- Keycloak link on Homepage
- Homepage values updates
- Pi-hole link updated to use DNS name

## [2026-03-10]

### Added
- Initial monitoring cluster commit with base infrastructure

## [2026-03-09]

### Fixed
- ArgoCD values file corrections and proper labeling
- ArgoCD icon updated
- Homepage links configured to open in new tab
- Updated `.gitignore` to include [AI_ASSISTANT] files

## [2026-03-08]

### Added
- Longhorn deployment to the monitoring cluster
- Proxmox credentials to Ansible configuration

### Changed
- Homepage configuration updates
- Application values updated for Longhorn storage
- GitHub bookmarks updated in Homepage to reflect correct VLAN naming

### Fixed
- Removed stale Prometheus and Loki entries from Homepage monitoring services
- Fixed path in `argocd.sh` script

## [2026-03-07]

### Added
- Grafana deployment and Helm chart configuration
- Grafana values and manifest files

### Changed
- Loki values updated
- Homepage values updated

## [2026-03-06]

### Added
- Initial manifests and DNS configuration
- Traefik IngressRoute manifests for monitoring services
