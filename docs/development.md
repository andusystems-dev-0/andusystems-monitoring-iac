# Development Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Ansible | 2.9+ | Playbook execution |
| Terraform | 1.x | Infrastructure provisioning |
| kubectl | matching cluster version | Kubernetes management |
| kubeadm | matching cluster version | Cluster bootstrapping |
| Helm | 3.x | Chart management |
| Python | 3.8+ | Ansible runtime |
| SSH client | any | VM access |

## Initial Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd andusystems-monitoring
```

### 2. Install Ansible Collections

```bash
cd ansible
ansible-galaxy install -r requirements.yml
```

This installs the `kubernetes.core` collection required for Kubernetes resource management.

### 3. Configure Ansible Vault

Create the vault file from the provided example:

```bash
cp ansible/inventory/monitoring/group_vars/all/vault.example \
   ansible/inventory/monitoring/group_vars/all/vault.yml
```

Edit `vault.yml` and fill in all required values (see [Configuration Reference](../README.md#configuration-reference)), then encrypt:

```bash
ansible-vault encrypt ansible/inventory/monitoring/group_vars/all/vault.yml
```

To edit the vault later:

```bash
ansible-vault edit ansible/inventory/monitoring/group_vars/all/vault.yml
```

### 4. Configure Terraform Variables

Populate the Terraform variables file at `terraform/terraform.tfvars` with values matching your Proxmox environment (API endpoint, node name, storage, networking).

### 5. SSH Key Setup

Ensure the SSH key specified in vault variable `ssh_key_path` exists and has access to the target VMs (or will be distributed during VM provisioning).

## Deployment Commands

All commands are run from the `ansible/` directory with the monitoring inventory.

### Full Stack Deployment

Deploys everything from VMs to applications:

```bash
cd ansible
ansible-playbook configurations/monitoring.yml \
  -i inventory/monitoring/hosts.yml \
  --ask-vault-pass
```

### Applications Only

Deploys all applications on an existing Kubernetes cluster:

```bash
ansible-playbook configurations/apps.yml \
  -i inventory/monitoring/hosts.yml \
  --ask-vault-pass
```

### Individual Components

Deploy specific components using standalone playbooks:

```bash
# Cert-Manager only
ansible-playbook configurations/cert-manager.yml \
  -i inventory/monitoring/hosts.yml \
  --ask-vault-pass

# Grafana only
ansible-playbook configurations/grafana.yml \
  -i inventory/monitoring/hosts.yml \
  --ask-vault-pass

# Homepage only
ansible-playbook configurations/homepage.yml \
  -i inventory/monitoring/hosts.yml \
  --ask-vault-pass

# Pangolin-Newt VPN only
ansible-playbook configurations/pangolin-newt.yml \
  -i inventory/monitoring/hosts.yml \
  --ask-vault-pass
```

Components without standalone playbooks (Prometheus, Loki, Tempo, Alloy, MetalLB) are deployed via `apps.yml` or the full `monitoring.yml` playbook.

## Project Structure

### Ansible Roles

Each role follows a consistent structure:

```
ansible/configurations/roles/<role-name>/
├── defaults/main.yml    # Default variables (usually empty, vault-driven)
├── tasks/
│   ├── main.yml         # Entry point (includes install.yml)
│   └── install.yml      # Installation tasks
```

**Role wrapper playbooks** (e.g., `roles/kubernetes.yml`, `roles/metallb.yml`) set host targeting and include the role.

### Application Configuration

Each application has its configuration in the `apps/` directory:

```
apps/<app-name>/
├── values.yml       # Helm chart values
└── manifest.yml     # Additional K8s manifests (IngressRoutes, Secrets, Certificates)
```

- **`values.yml`** -- Helm values passed during chart installation
- **`manifest.yml`** -- Raw Kubernetes manifests applied via `kubernetes.core.k8s` (IngressRoutes, ClusterIssuers, Secrets, etc.)

### Terraform Layers

```
terraform/layers/
├── layer-1-infrastructure/   # Proxmox VM provisioning
└── layer-2-helmapps/         # Helm chart deployment via Terraform
```

Layer 1 is called by the `vms` Ansible role; Layer 2 is called by the `metallb` role.

## Environment Variables

Ansible Vault handles all secrets. No environment variables need to be set for standard deployment. The Ansible configuration at `ansible/ansible.cfg` disables host key checking and logs output to `ansible.log`.

## Modifying Applications

### Updating Helm Values

1. Edit the relevant `apps/<app>/values.yml`
2. Re-run the corresponding Ansible playbook or role
3. The role will apply the updated values via Helm

### Adding a New Application

1. Create `apps/<new-app>/values.yml` (and optionally `manifest.yml`)
2. Create an Ansible role under `ansible/configurations/roles/<new-app>/`
3. Add the role to `ansible/configurations/apps.yml` in the correct deployment order
4. Add any required vault variables to `ansible/inventory/monitoring/group_vars/all/vars.yml`
5. Update the vault example with placeholder values

### Modifying Kubernetes Manifests

Manifests in `apps/<app>/manifest.yml` are applied via the `kubernetes.core.k8s` Ansible module. Edit the manifest and re-run the playbook to apply changes.

## Verification Commands

After deployment, verify the cluster state:

```bash
# Check all pods are running
kubectl get pods -A

# Verify Prometheus is scraping targets
kubectl port-forward -n prometheus svc/monitoring-kube-prometheus-prometheus 9090
# Then visit http://localhost:9090/targets

# Verify Loki is receiving logs
kubectl logs -n loki -l app.kubernetes.io/name=loki --tail=20

# Verify Alloy DaemonSets are running on all nodes
kubectl get daemonsets -A | grep alloy

# Check certificate status
kubectl get certificates -A
```

## Utility Scripts

Helper scripts are available in the `scripts/` directory:

| Script | Purpose |
|--------|---------|
| `scripts/vms.sh` | VM provisioning operations |
| `scripts/kubernetes.sh` | Kubernetes cluster operations |
| `scripts/apps.sh` | Application deployment |
| `scripts/redeploy.sh` | Full redeployment automation |

## Troubleshooting

### Alloy OOMKilled

If Alloy pods are repeatedly killed due to memory limits, increase the resource limits in `apps/alloy/values.yml` for the affected sub-chart (`alloy-metrics`, `alloy-logs`, `alloy-singleton`, or `alloy-receiver`). The metrics DaemonSet is the most resource-intensive component.

### Cert-Manager CRD Readiness

The Prometheus and cert-manager roles wait for CRDs to become available (up to 30 retries with 10-second delays). If deployment fails due to CRD timeouts, verify the CRD installation completed successfully:

```bash
kubectl get crds | grep cert-manager
kubectl get crds | grep monitoring.coreos.com
```

### Grafana Login Issues

Grafana uses Keycloak OIDC for authentication. If login fails, verify:
- The OIDC client secret matches the Keycloak configuration
- The Keycloak realm and client are properly configured
- Grafana's root URL matches the external ingress URL
- The `grafana-oidc-secret` Kubernetes secret exists and has the correct value

### Loki Not Receiving Logs

If logs are not appearing in Grafana:
- Check that Alloy logs DaemonSet pods are running on all nodes: `kubectl get ds -n alloy`
- Verify Loki is healthy: `kubectl get pods -n loki`
- Check Alloy logs for push errors: `kubectl logs -n alloy -l app.kubernetes.io/name=alloy-logs --tail=50`
- Ensure the MinIO S3 endpoint is accessible from the monitoring cluster

### MetalLB Not Assigning IPs

If services remain in `Pending` state:
- Verify the IPAddressPool resource exists: `kubectl get ipaddresspools -A`
- Verify the L2Advertisement resource exists: `kubectl get l2advertisements -A`
- Ensure the configured IP range does not conflict with other allocations on the network
