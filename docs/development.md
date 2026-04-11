# Development Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Ansible | 2.15+ | Configuration management and deployment |
| Terraform | 1.5+ | VM provisioning on Proxmox |
| kubectl | 1.31+ | Kubernetes cluster interaction |
| Helm | 3.x | Chart-based application deployment |
| SSH | — | Node access for Ansible |

### Ansible Collections

Install required collections before running any playbook:

```bash
ansible-galaxy collection install -r ansible/requirements.yml
```

This installs:
- `kubernetes.core` — provides `k8s`, `helm`, and `kubectl` modules

## Environment Setup

### 1. Ansible Vault

All secrets are stored in an encrypted Ansible Vault file. Copy the example and fill in values:

```bash
cp ansible/inventory/monitoring/group_vars/all/vault.example \
   ansible/inventory/monitoring/group_vars/all/vault
ansible-vault encrypt ansible/inventory/monitoring/group_vars/all/vault
```

Required vault variables include credentials for: Proxmox API, Cloudflare DNS, MinIO object storage, Grafana admin/OIDC, and VPN tunnel configuration. See the vault example file for the complete list.

### 2. SSH Access

Ansible connects to cluster nodes via SSH. Ensure your SSH key is distributed to all target nodes. The VM provisioning role handles initial key distribution automatically during the Terraform/Ansible bootstrap.

### 3. Kubeconfig

After cluster bootstrap, the Ansible Kubernetes role exports a kubeconfig to the repository root. This file is gitignored and used by subsequent playbooks for `kubectl` and `helm` operations.

## Deployment Commands

### Full Stack Deployment

Provisions VMs, bootstraps Kubernetes, and deploys all applications:

```bash
./scripts/redeploy.sh
# Equivalent to:
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/monitoring.yml \
  --tags vms,kubernetes,apps,install -K
```

### Individual Components

**Provision VMs (Terraform via Ansible):**

```bash
./scripts/vms.sh
# Equivalent to:
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/roles/vms.yml \
  --tags vms -K
```

**Bootstrap Kubernetes:**

```bash
./scripts/kubernetes.sh
# Equivalent to:
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/roles/kubernetes.yml \
  --tags kubernetes,install
```

**Deploy Applications Only:**

```bash
./scripts/apps.sh
# Equivalent to:
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/apps.yml \
  --tags apps,install -K
```

### Individual Application Playbooks

Each application has a standalone playbook for targeted deployment:

```bash
# Cert-Manager
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/cert-manager.yml --tags cert-manager,install

# Grafana
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/grafana.yml --tags grafana,install

# Homepage
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/homepage.yml --tags homepage,install
```

## Application Deployment Order

The `apps.yml` playbook enforces a specific installation order due to component dependencies:

```
1. MetalLB          ← Load balancer (required by all services)
2. Cert-Manager     ← TLS certificates (required by ingress)
3. Pangolin-Newt    ← VPN tunnel agent
4. Prometheus       ← Metrics collection (kube-prometheus-stack)
5. Loki             ← Log aggregation
6. Tempo            ← Distributed tracing
7. Alloy            ← Telemetry collectors
8. Homepage         ← Operational dashboard
9. Grafana          ← Visualization (depends on Prometheus, Loki, Tempo)
```

## Modifying Helm Values

Application configurations live in `apps/<component>/values.yml`. These files are Jinja2 templates processed by Ansible at deploy time, meaning they can reference Ansible variables (including vault secrets).

To update a component's configuration:

1. Edit the relevant `apps/<component>/values.yml`
2. Re-run the component's playbook or the full `apps.yml` playbook
3. ArgoCD will detect the drift and can sync the changes going forward

### Common Configuration Tasks

**Adjust resource limits:** Edit the `resources` block in the component's `values.yml`. All components define both `requests` and `limits` for CPU and memory.

**Add a Grafana datasource:** Add a new entry under `grafana.datasources` in `apps/grafana/values.yml` with the appropriate type (`prometheus`, `loki`, or `tempo`) and target URL.

**Add a Grafana dashboard:** Add an entry to `grafana.dashboardProviders` and `grafana.dashboardsConfigMaps` or use `grafana.dashboards` with a Grafana.com `gnetId` reference in `apps/grafana/values.yml`.

**Modify Prometheus retention:** Update the `prometheus.prometheusSpec.retention` field in `apps/prometheus/values.yml`.

**Adjust Loki retention:** Modify the `loki.limits_config.retention_period` field in `apps/loki/values.yml`.

## Adding a New Monitored Cluster

To add a new remote cluster to the centralized monitoring:

1. Deploy Prometheus, Loki, and Tempo on the new cluster (each exposed via MetalLB)
2. Add datasource entries to `apps/grafana/values.yml` pointing to the new cluster's service IPs
3. Redeploy Grafana

## Ansible Role Structure

Each role follows a consistent pattern:

```
roles/<component>/
├── defaults/main.yml    # Default variable values (if any)
├── tasks/
│   ├── main.yml         # Task dispatcher (includes install.yml)
│   └── install.yml      # Installation tasks
```

Roles are invoked from wrapper playbooks (e.g., `roles/kube-prometheus-stack.yml` invokes the role on the controllers group). Most roles target the `controllers` host group since they interact with the Kubernetes API via the control-plane node.

## Terraform Integration

The VM provisioning role wraps Terraform execution within Ansible:

1. Runs `terraform destroy` to clean up existing VMs
2. Runs `terraform apply` to provision new VMs from Proxmox templates
3. Configures SSH access to the newly created nodes

Terraform state and variable files (`.tfvars`, `.tfstate`) are gitignored.

## Troubleshooting

**Ansible vault errors:** Ensure the vault file exists and you have the correct vault password. Use `--ask-vault-pass` if not using a password file.

**Kubernetes join failures:** The Kubernetes role includes retry logic for worker node joins. If joins still fail, verify network connectivity between nodes and check that the control plane is healthy.

**CRD registration delays:** Some roles (cert-manager, kube-prometheus-stack) wait for CRDs to register before proceeding. If timeouts occur, verify the CRD installation succeeded with `kubectl get crds`.

**Alloy OOMKilled:** If Alloy pods are killed due to memory limits, increase the memory limits in `apps/alloy/values.yml` under the appropriate sub-chart section.
