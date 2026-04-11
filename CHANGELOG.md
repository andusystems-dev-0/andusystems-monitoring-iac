# Changelog

All notable changes to the andusystems-monitoring repository are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2026-04-05]

### Fixed
- Bumped Alloy resource limits to fix OOMKilled pod restarts

## [2026-03-23]

### Fixed
- Grafana values updated to fix login issues temporarily
- Grafana auto-redirect to Keycloak login configured
- Grafana Keycloak OIDC login integration added
- Traefik CRD installation added to monitoring cluster

### Changed
- Grafana values updated for correct load balancer IPs for networking cluster datasources
- Various small fixes across configurations

## [2026-03-17]

### Added
- Ansible deployment of LGTM (Loki, Grafana, Tempo, Metrics) stack
- Grafana dashboards and datasource provisioning
- Grafana values with pre-configured dashboards and multi-cluster datasources

### Changed
- Updated Grafana values for correct load balancer IPs on datasources
- Removed MinIO deployment from monitoring cluster in favor of centralized MinIO on storage cluster

### Fixed
- Fixes to the LGTM stack configuration and connectivity

## [2026-03-15]

### Added
- Grafana Helm values files
- MetalLB deployment to monitoring cluster

## [2026-03-14]

### Added
- Homepage values with infrastructure services and links
- Networking repository link added to Homepage

### Changed
- Homepage values updated with new services and correct formatting
- Homepage widget sizing adjusted
- Pi-hole homepage link updated to use DNS name

### Fixed
- Keycloak link on Homepage corrected

## [2026-03-10]

### Added
- Initial project structure and configuration

## [2026-03-09]

### Added
- Homepage dashboard with service links and bookmarks
- ArgoCD configuration and values

### Fixed
- ArgoCD values file formatting and labeling
- Homepage links configured to open in new tabs
- ArgoCD icon on Homepage

### Changed
- Gitignore updated to exclude [AI_ASSISTANT] workspace files

## [2026-03-08]

### Added
- Longhorn storage deployment to monitoring cluster
- Proxmox credentials added to Ansible configuration
- Homepage dashboard initial deployment

### Changed
- Application values updated for Longhorn storage integration
- Homepage configuration refined with correct service entries
- GitHub bookmarks updated to reflect correct naming

### Removed
- Prometheus and Loki entries from monitoring services in Homepage (moved to dedicated section)

## [2026-03-07]

### Changed
- Loki values updated
