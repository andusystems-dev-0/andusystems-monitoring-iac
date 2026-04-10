# Development & Deployment Guide

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| **Terraform** | VM provisioning on Proxmox | [terraform.io](https://www.terraform.io/downloads) |
| **Ansible** | Cluster bootstrapping and app deployment | `pip install ansible` |
| **kubectl** | Kubernetes cluster interaction | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** (optional) | Chart inspection/debugging | [helm.sh](https://helm.sh/docs/intro/install/) |
| **SSH access** | Connectivity to cluster nodes | SSH key configured in vault |

### Ansible Dependencies

Install the required Ansible collection:

```bash
ansible-galaxy install -r ansible/requirements.yml
```

This installs the `kubernetes.core` collection used by all application roles.

### Terraform Variables

Each Terraform layer requires a `terraform.tfvars` file (gitignored). See the `variables.tf` in each layer for required values:

- `terraform/layers/layer-1-infrastructure/` — Proxmox API credentials, node assignments, VM specs, network config
- `terraform/layers/layer-2-helmapps/` — Kubeconfig path for Helm provider

### Ansible Vault

All secrets are encrypted with Ansible Vault. The vault password is required for any deployment operation. A reference template is available at:

```
ansible/inventory/monitoring/group_vars/all/vault.example
```

## Deployment

### Full Redeployment

Tears down and rebuilds the entire stack (VMs, Kubernetes, and all applications):

```bash
./scripts/redeploy.sh
```

This runs the master playbook `ansible/configurations/monitoring.yml` with all tags: `vms`, `kubernetes`, `apps`, `install`. Requires sudo password (`-K` flag).

### Layer-by-Layer Deployment

#### 1. Provision VMs

```bash
./scripts/vms.sh
```

Runs Terraform to create/recreate VMs on Proxmox, then configures SSH access (host keys, authorized keys). Requires sudo password.

**What it does:**
1. Destroys existing Terraform state (clean slate)
2. Applies Terraform to provision VMs with Ubuntu cloud images
3. Updates `/etc/hosts` with new VM IPs
4. Configures SSH known hosts and key-based authentication

#### 2. Bootstrap Kubernetes

```bash
./scripts/kubernetes.sh
```

Installs and configures Kubernetes on all provisioned VMs.

**What it does:**
1. Configures system prerequisites (swap disabled, kernel modules, sysctl)
2. Installs containerd with SystemdCgroup
3. Installs kubeadm, kubelet, kubectl (version-pinned)
4. Initializes the control plane with the configured pod CIDR
5. Deploys Flannel CNI
6. Joins worker nodes to the cluster
7. Fetches kubeconfig to the repository root

#### 3. Deploy Applications

```bash
./scripts/apps.sh
```

Deploys all monitoring stack applications in the correct order. Requires sudo password.

**Deployment order:**
1. MetalLB (load balancer)
2. Cert-Manager (TLS certificates)
3. Pangolin-Newt (VPN tunnel)
4. kube-prometheus-stack (Prometheus + Alertmanager + exporters)
5. Loki (log aggregation)
6. Tempo (distributed tracing)
7. Alloy (telemetry collector)
8. Homepage (dashboard)
9. Grafana (visualization)

### ArgoCD

```bash
./scripts/argocd.sh
```

Installs a cluster-local ArgoCD instance (managed by the central ArgoCD on the management cluster for ongoing GitOps reconciliation).

## Project Layout

### Ansible Structure

```
ansible/
├── ansible.cfg                           # Ansible configuration
├── requirements.yml                      # Galaxy dependencies
├── inventory/monitoring/
│   ├── hosts.yml                         # Node definitions and groups
│   └── group_vars/all/
│       ├── vars.yml                      # Variable definitions (references vault)
│       └── vault.example                 # Vault template
└── configurations/
    ├── monitoring.yml                    # Master orchestration (imports all)
    ├── apps.yml                          # App deployment orchestration
    ├── cert-manager.yml                  # Cert-manager playbook
    ├── grafana.yml                       # Grafana playbook
    ├── homepage.yml                      # Homepage playbook
    ├── pangolin-newt.yml                 # VPN client playbook
    └── roles/
        ├── vms.yml                       # VM provisioning role entry
        ├── vms/tasks/{main,install}.yml
        ├── kubernetes.yml                # K8s bootstrap role entry
        ├── kubernetes/tasks/{main,install}.yml
        ├── metallb.yml
        ├── metallb/tasks/{main,install}.yml
        ├── kube-prometheus-stack.yml
        ├── kube-prometheus-stack/tasks/{main,install}.yml
        ├── loki.yml
        ├── loki/tasks/{main,install}.yml
        ├── tempo.yml
        ├── tempo/tasks/{main,install}.yml
        ├── alloy.yml
        ├── alloy/tasks/{main,install}.yml
        ├── grafana/tasks/{main,install}.yml
        ├── homepage/tasks/{main,install}.yml
        ├── cert-manager/tasks/{main,install}.yml
        └── pangolin-newt/tasks/{main,install}.yml
```

### Application Manifests

Each application under `apps/` typically contains:

- **`values.yml`** — Helm chart values (resource limits, storage, feature flags)
- **`manifest.yml`** — Kubernetes resources applied directly (IngressRoutes, Secrets, Certificates, CRDs)

### Terraform Layers

| Layer | Path | Purpose |
|---|---|---|
| Layer 1 | `terraform/layers/layer-1-infrastructure/` | Proxmox VM provisioning |
| Layer 2 | `terraform/layers/layer-2-helmapps/` | MetalLB Helm chart installation |

## Modifying Components

### Updating Helm Values

Edit the `values.yml` for the target component under `apps/<component>/`. Then redeploy:

```bash
# Redeploy all apps
./scripts/apps.sh

# Or target a specific component via Ansible tags
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/apps.yml \
  --tags <component>,install
```

### Adding a New Application

1. Create a directory under `apps/<new-app>/` with `values.yml` and optionally `manifest.yml`
2. Create an Ansible role under `ansible/configurations/roles/<new-app>/` with `tasks/main.yml` and `tasks/install.yml`
3. Add the role import to `ansible/configurations/apps.yml`
4. If the app needs a namespace, create it in the install task
5. If the app needs secrets, add vault variables and create the Kubernetes secret in the install task

### Changing Kubernetes Version

The Kubernetes version is controlled by a vault variable. Update it there, then re-run:

```bash
./scripts/kubernetes.sh
```

This will reset and reinitialize the cluster with the new version.

### Modifying VM Resources

Edit the Terraform variables in `terraform/layers/layer-1-infrastructure/terraform.tfvars`, then:

```bash
./scripts/vms.sh
```

Note: This destroys and recreates all VMs (clean-slate approach).

## Environment Variables

All configuration is managed through Ansible Vault rather than environment variables. The vault file contains values for:

| Category | Examples |
|---|---|
| **SSH/Network** | SSH user, key path, node IPs, pod CIDR |
| **Kubernetes** | K8s version, kubeconfig path |
| **Cloud** | Cloudflare API token, Proxmox credentials |
| **Storage** | MinIO credentials |
| **Applications** | Grafana admin creds, OIDC client secret, Let's Encrypt email |
| **VPN** | Pangolin endpoint, Newt ID and secret |
| **Network** | MetalLB IP range |

## Troubleshooting

### SSH Connectivity

If Ansible cannot reach nodes after VM provisioning, the VM role automatically handles SSH key scanning and distribution. If issues persist, check:

- VM IPs match inventory
- SSH key is correctly configured in vault
- `/etc/hosts` on the Ansible controller has the correct entries

### Helm Deployment Failures

Application roles apply Helm charts via `kubernetes.core.helm`. If a deployment fails:

1. Check the Ansible output for the specific error
2. Verify CRDs are installed (Prometheus Operator and cert-manager CRDs are installed before their charts)
3. Check namespace exists
4. Verify secrets are created (MinIO creds for Loki/Tempo, Grafana OIDC secret)

### Storage Issues

Longhorn must be healthy before deploying stateful applications. Verify:

```bash
kubectl get nodes   # All nodes should be Ready
kubectl -n longhorn-system get pods   # All Longhorn pods should be Running
```

### CRD Ordering

Some components require CRDs to be registered before Helm charts are applied:

- **cert-manager**: CRDs installed from GitHub release before chart
- **kube-prometheus-stack**: Prometheus Operator CRDs installed before chart
- **MetalLB**: Deployed via Terraform Helm before IPAddressPool/L2Advertisement resources
