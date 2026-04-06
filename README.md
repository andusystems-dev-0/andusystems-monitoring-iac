# andusystems-monitoring

Infrastructure-as-Code repository for the Andu Systems monitoring cluster. Deploys a complete Kubernetes-based observability platform using Ansible and Terraform, providing centralized metrics, logging, and tracing across a multi-cluster environment.

## Overview

This repository automates the full lifecycle of the monitoring cluster:

1. **VM provisioning** on a Proxmox hypervisor via Terraform
2. **Kubernetes cluster bootstrapping** via kubeadm with Ansible
3. **Observability stack deployment** (LGTM: Loki, Grafana, Tempo, Metrics/Prometheus)
4. **Supporting infrastructure** (ingress, load balancing, TLS, VPN, dashboard)

## Architecture

The monitoring cluster is part of a segmented multi-VLAN infrastructure:

| Segment | Purpose |
|---------|---------|
| Management | Internal services, SSO, secrets management, CI/CD |
| DMZ | Publicly-exposed password manager |
| Public Applications | User-facing services |
| Storage | Centralized object storage, persistent volumes, backups |
| **Monitoring** | **This cluster** -- observability, dashboards, alerting |

See [docs/architecture.md](docs/architecture.md) for detailed component diagrams and data flows.

## Stack Components

| Component | Purpose | Helm Chart |
|-----------|---------|------------|
| **Prometheus** | Metrics collection and alerting | `kube-prometheus-stack` |
| **Loki** | Log aggregation (S3-backed) | `loki` |
| **Tempo** | Distributed tracing (S3-backed) | `tempo` |
| **Grafana** | Visualization and dashboarding | `grafana` |
| **Alloy** | Unified telemetry collection (metrics, logs, traces) | `alloy` |
| **Traefik** | Ingress controller with TLS termination | `traefik` |
| **MetalLB** | Bare-metal load balancer (L2 mode) | `metallb` |
| **Cert-Manager** | Automatic TLS certificates via Let's Encrypt | `cert-manager` |
| **Longhorn** | Distributed block storage | `longhorn` |
| **Homepage** | Unified dashboard for service access | `homepage` |
| **Pangolin-Newt** | VPN client for secure admin access | `pangolin-newt` |

Grafana aggregates telemetry from all clusters into a single pane of glass, with each remote cluster running its own Alloy collector that pushes metrics, logs, and traces to the monitoring cluster.

See [docs/architecture.md](docs/architecture.md) for detailed component diagrams and data flows.

## Quick Start

### Prerequisites

- Ansible 2.9+ with `kubernetes.core` collection
- Terraform 1.x
- `kubectl` and `kubeadm`
- Helm 3.x
- Access to the Proxmox hypervisor
- Ansible Vault password for decrypting secrets
- Cloudflare API token (for DNS-based TLS challenges)

### Install Dependencies

```bash
cd ansible
ansible-galaxy install -r requirements.yml
```

### Configure Vault

Copy the vault example and populate with real values:

```bash
cp ansible/inventory/monitoring/group_vars/all/vault.example \
   ansible/inventory/monitoring/group_vars/all/vault.yml
ansible-vault encrypt ansible/inventory/monitoring/group_vars/all/vault.yml
```

### Deploy

Run the full deployment (VMs, Kubernetes, all applications):

```bash
cd ansible
ansible-playbook configurations/monitoring.yml \
  -i inventory/monitoring/hosts.yml \
  --ask-vault-pass
```

Or deploy only applications on an existing cluster:

```bash
ansible-playbook configurations/apps.yml \
  -i inventory/monitoring/hosts.yml \
  --ask-vault-pass
```

See [docs/development.md](docs/development.md) for individual component deployment and troubleshooting.

## Configuration Reference

All sensitive and environment-specific values are stored in Ansible Vault. See `vault.example` for a complete template.

### Infrastructure Variables

| Variable | Description |
|----------|-------------|
| `repo_root` | Absolute path to the repository root |
| `ssh_user` | SSH user for VM access |
| `ssh_key_path` | Path to SSH private key |
| `control_plane_ip` | IP address of the control plane node |
| `worker_ips` | List of worker node IP addresses |
| `kubernetes_version` | Kubernetes version to install (e.g., `1.31`) |
| `pod_network_cidr` | CIDR range for pod networking |
| `proxmox_api_token_id` | Proxmox API token ID for Terraform |
| `proxmox_api_token_secret` | Proxmox API token secret for Terraform |

### Networking and TLS Variables

| Variable | Description |
|----------|-------------|
| `cloudflare_api_token` | Cloudflare API token for DNS01 challenges |
| `letsencrypt_email` | Email for Let's Encrypt registration |
| `metallb_ip_range` | IP range for MetalLB load balancer pool |
| `pangolin_endpoint` | Pangolin VPN endpoint |
| `newt_id` | Pangolin Newt client ID |
| `newt_secret` | Pangolin Newt client secret |
| `homepage_url` | URL for the Homepage dashboard |

### Application Variables

| Variable | Description |
|----------|-------------|
| `grafana_admin_user` | Grafana admin username |
| `grafana_admin_password` | Grafana admin password |
| `grafana_oidc_client_secret` | OIDC client secret for Keycloak SSO |
| `minio_root_user` | MinIO root username (for Loki/Tempo S3 access) |
| `minio_root_password` | MinIO root password (for Loki/Tempo S3 access) |

## Repository Structure

```
.
├── ansible/
│   ├── ansible.cfg                  # Ansible configuration
│   ├── requirements.yml             # Collection dependencies (kubernetes.core)
│   ├── inventory/monitoring/        # Inventory and variables
│   │   ├── hosts.yml                # Host definitions
│   │   └── group_vars/all/
│   │       ├── vars.yml             # Variable definitions (vault-templated)
│   │       └── vault.example        # Vault template
│   └── configurations/
│       ├── monitoring.yml           # Main playbook (full deployment)
│       ├── apps.yml                 # Application-only deployment
│       ├── cert-manager.yml         # Cert-Manager standalone playbook
│       ├── grafana.yml              # Grafana standalone playbook
│       ├── homepage.yml             # Homepage standalone playbook
│       ├── pangolin-newt.yml        # VPN client standalone playbook
│       └── roles/                   # Ansible roles per component
├── apps/                            # Helm values and K8s manifests per app
│   ├── alloy/
│   ├── cert-manager/
│   ├── grafana/
│   ├── homepage/
│   ├── loki/
│   ├── longhorn/
│   ├── metallb/
│   ├── pangolin-newt/
│   ├── prometheus/
│   ├── tempo/
│   └── traefik/
├── terraform/layers/                # Terraform modules
│   ├── layer-1-infrastructure/      # VM provisioning on Proxmox
│   └── layer-2-helmapps/            # Helm chart deployment
├── scripts/                         # Utility scripts
└── docs/                            # Documentation
```

## Further Documentation

- [Architecture](docs/architecture.md) -- Component diagram, data flows, design decisions
- [Development Guide](docs/development.md) -- Local setup, deployment commands, troubleshooting
- [Changelog](CHANGELOG.md) -- Release history
