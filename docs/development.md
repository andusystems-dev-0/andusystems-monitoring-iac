# Development Guide

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| **Ansible** | Orchestration and configuration management | [docs.ansible.com](https://docs.ansible.com/ansible/latest/installation_guide/) |
| **Terraform** | Infrastructure provisioning (Proxmox VMs, Helm releases) | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| **kubectl** | Kubernetes CLI | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| **Helm 3** | Kubernetes package manager | [helm.sh](https://helm.sh/docs/intro/install/) |
| **SSH key pair** | Node access | `ssh-keygen` |
| **Access to Proxmox** | VM hypervisor | Requires API token |

## Local Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd andusystems-monitoring
```

### 2. Install Ansible Dependencies

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

This installs the `kubernetes.core` collection required for Kubernetes resource management from Ansible.

### 3. Configure Ansible Vault

```bash
cp ansible/inventory/monitoring/group_vars/all/vault.example \
   ansible/inventory/monitoring/group_vars/all/vault
```

Edit the vault file and populate all required secrets. Encrypt it with:

```bash
ansible-vault encrypt ansible/inventory/monitoring/group_vars/all/vault
```

### 4. Verify Inventory

Review `ansible/inventory/monitoring/hosts.yml` to ensure host definitions match your environment. The inventory defines controller and worker nodes with IP addresses sourced from vault variables.

### 5. Fetch Kubeconfig

After the cluster is provisioned, the kubeconfig is stored at the repository root. Set your context:

```bash
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

## Environment Variables

All sensitive configuration is managed through Ansible Vault. The following variables must be defined:

### SSH & Node Access

| Variable | Description |
|---|---|
| `ssh_user` | SSH username for cluster nodes |
| `ssh_key_path` | Path to SSH private key |

### Kubernetes

| Variable | Description |
|---|---|
| `kubernetes_version` | Target Kubernetes version for kubeadm |
| `pod_network_cidr` | CIDR for Flannel pod networking |

### Infrastructure

| Variable | Description |
|---|---|
| `proxmox_api_token_id` | Proxmox API token ID |
| `proxmox_api_token_secret` | Proxmox API token secret |
| `control_plane_ip` | IP address for the control plane node |
| `worker_ips` | List of worker node IP addresses |
| `metallb_ip_range` | IP range for MetalLB load balancer pool |

### TLS / DNS

| Variable | Description |
|---|---|
| `cloudflare_api_token` | CloudFlare API token for DNS-01 challenges |
| `letsencrypt_email` | Email for Let's Encrypt certificate registration |

### Observability Stack

| Variable | Description |
|---|---|
| `grafana_admin_user` | Grafana admin username |
| `grafana_admin_password` | Grafana admin password |
| `grafana_oidc_client_secret` | Keycloak OIDC client secret for Grafana |
| `minio_root_user` | MinIO access key (S3 backend for Loki/Tempo) |
| `minio_root_password` | MinIO secret key |

### Tunnel

| Variable | Description |
|---|---|
| `pangolin_endpoint` | Pangolin Newt endpoint |
| `pangolin_id` | Pangolin Newt client ID |
| `pangolin_secret` | Pangolin Newt client secret |

## Deployment Commands

### Full Stack Deployment

Provisions VMs, bootstraps Kubernetes, and deploys all applications:

```bash
ansible-playbook ansible/configurations/monitoring.yml \
  -i ansible/inventory/monitoring/hosts.yml \
  --ask-vault-pass
```

### Application-Only Deployment

Deploys all Helm applications (assumes cluster is already running):

```bash
ansible-playbook ansible/configurations/apps.yml \
  -i ansible/inventory/monitoring/hosts.yml \
  --ask-vault-pass
```

### Individual Component Deployment

Each component can be deployed independently:

```bash
# Cert-Manager
ansible-playbook ansible/configurations/cert-manager.yml \
  -i ansible/inventory/monitoring/hosts.yml --ask-vault-pass

# Grafana
ansible-playbook ansible/configurations/grafana.yml \
  -i ansible/inventory/monitoring/hosts.yml --ask-vault-pass

# Homepage
ansible-playbook ansible/configurations/homepage.yml \
  -i ansible/inventory/monitoring/hosts.yml --ask-vault-pass
```

For roles that are included in `apps.yml` but don't have standalone playbooks (e.g., Loki, Tempo, Alloy), use tags:

```bash
ansible-playbook ansible/configurations/apps.yml \
  -i ansible/inventory/monitoring/hosts.yml \
  --ask-vault-pass \
  --tags apps
```

## Deployment Order

Components must be deployed in this order (handled automatically by `monitoring.yml`):

1. **VMs** — Proxmox VM provisioning via Terraform
2. **Kubernetes** — kubeadm cluster bootstrap with Flannel CNI
3. **MetalLB** — Load balancer (required by Traefik)
4. **Cert-Manager** — TLS certificates (required by IngressRoutes)
5. **Pangolin Newt** — Tunnel agent
6. **Kube-Prometheus-Stack** — Prometheus, Alertmanager, CRDs
7. **Loki** — Log aggregation
8. **Tempo** — Distributed tracing
9. **Alloy** — Unified telemetry collector
10. **Homepage** — Dashboard portal
11. **Grafana** — Visualization (depends on all datasource backends being available)

## Modifying Helm Values

Application Helm values are stored in `apps/<component>/values.yml`. After modifying values:

1. Edit the values file
2. Re-run the component's Ansible playbook or the full `apps.yml` playbook
3. Terraform will detect the change and update the Helm release

### Key Files to Edit

| What to Change | File |
|---|---|
| Alloy collector config, destinations, resource limits | `apps/alloy/values.yml` |
| Cert-Manager replicas, DNS resolvers | `apps/cert-manager/values.yml` |
| Grafana datasources, OIDC config, dashboards | `apps/grafana/values.yml` |
| Homepage layout, services, bookmarks | `apps/homepage/values.yml` |
| Loki retention, storage, ingestion limits | `apps/loki/values.yml` |
| Longhorn replica count, storage settings | `apps/longhorn/manifest.yml` |
| Prometheus retention, storage, scrape config | `apps/prometheus/values.yml` (via Terraform) |
| Tempo storage, OTLP receivers | `apps/tempo/values.yml` (via Terraform) |

## Adding a New Monitored Cluster

To add a new remote cluster's observability data to Grafana:

1. Deploy the LGTM stack on the remote cluster
2. Ensure the remote Prometheus, Loki, and Tempo endpoints are reachable from the monitoring cluster
3. Add new datasource entries in `apps/grafana/values.yml` under the `datasources` section
4. Re-deploy Grafana

## Ansible Configuration

The Ansible configuration (`ansible/ansible.cfg`) is set up for this project's inventory structure. Key settings:

- Inventory path: `ansible/inventory/monitoring/hosts.yml`
- Vault file: `ansible/inventory/monitoring/group_vars/all/vault`
- SSH configuration: retry interval and connection timeout defined in vault variables

## Troubleshooting

### Common Issues

**Terraform state conflicts**: The VMs and Helm roles run `terraform destroy` before `terraform apply`. If state is corrupted, manually clean up Terraform state files.

**Cert-Manager CRD race condition**: The kube-prometheus-stack and cert-manager roles wait for CRDs to be registered. If deployment fails with "CRD not found", re-run the playbook — CRD registration can take a few seconds.

**Alloy OOMKilled**: If Alloy pods are evicted due to memory limits, increase resource limits in `apps/alloy/values.yml` under the relevant Alloy sub-component (`alloy-metrics`, `alloy-logs`, `alloy-singleton`, `alloy-receiver`).

**Grafana OIDC login issues**: Ensure the Keycloak realm and client are configured correctly. The `grafana_oidc_client_secret` in vault must match the Keycloak client secret. Check `apps/grafana/values.yml` for the OAuth configuration.

**Worker node join failures**: The Kubernetes role retries worker joins with `--ignore-preflight-errors`. If a node still fails to join, SSH into the node and check `journalctl -u kubelet` for details.
