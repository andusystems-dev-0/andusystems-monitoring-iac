# Development

This document covers local setup, how to run individual playbooks, available Ansible tags,
and common troubleshooting steps.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Ansible | 2.15+ | `pip install ansible` |
| Python | 3.10+ | System or pyenv |
| kubernetes.core | latest | `ansible-galaxy collection install -r ansible/requirements.yml` |
| kubectl | 1.31 | [kubernetes.io/docs](https://kubernetes.io/docs/tasks/tools/) |
| Terraform | 1.6+ | [developer.hashicorp.com](https://developer.hashicorp.com/terraform/install) |
| Helm | 3.14+ | [helm.sh/docs](https://helm.sh/docs/intro/install/) |
| ansible-vault | bundled | Included with Ansible |

## Initial setup

### 1. Clone and install collections

```bash
git clone <internal-git-host>/andusystems/andusystems-monitoring.git
cd andusystems-monitoring
ansible-galaxy collection install -r ansible/requirements.yml
```

### 2. Configure the vault

```bash
cp ansible/inventory/monitoring/group_vars/all/vault.example \
   ansible/inventory/monitoring/group_vars/all/vault.yml
```

Edit `vault.yml` and replace every placeholder with a real value. Then encrypt it:

```bash
ansible-vault encrypt ansible/inventory/monitoring/group_vars/all/vault.yml
```

To edit an encrypted vault file later:

```bash
ansible-vault edit ansible/inventory/monitoring/group_vars/all/vault.yml
```

### 3. Verify connectivity

```bash
ansible -i ansible/inventory/monitoring all -m ping --ask-vault-pass
```

## Playbook reference

The top-level playbook `ansible/configurations/monitoring.yml` imports three sub-playbooks in
order:

| Sub-playbook | What it does |
|---|---|
| `roles/vms.yml` | Provisions VMs via Terraform, distributes SSH keys |
| `roles/kubernetes.yml` | Bootstraps Kubernetes (kubeadm, Flannel, kubeconfig) |
| `apps.yml` | Deploys all cluster applications |

`apps.yml` itself imports application roles in this order:

1. metallb
2. cert-manager
3. pangolin-newt
4. kube-prometheus-stack
5. loki
6. tempo
7. alloy
8. homepage
9. grafana

## Ansible tags

Run only the parts you need with `--tags`. Tags can be combined.

| Tag | Scope |
|---|---|
| `vms` | VM provisioning and SSH key distribution |
| `kubernetes` | Kubernetes cluster bootstrap |
| `apps` | All application deployments |
| `install` | Install tasks within any role |
| `metallb` | MetalLB only |
| `cert-manager` | cert-manager only |
| `newt` | Pangolin/Newt VPN client only |
| `kube-prometheus-stack` | Prometheus stack only |
| `loki` | Loki only |
| `tempo` | Tempo only |
| `alloy` | Alloy collector only |
| `homepage` | Homepage dashboard only |
| `grafana` | Grafana only |

### Examples

```bash
# Full stack (VMs + Kubernetes + apps)
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/monitoring.yml --ask-vault-pass

# Apps only (cluster already running)
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/monitoring.yml --ask-vault-pass --tags apps

# Grafana only (e.g. after updating apps/grafana/values.yml)
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/monitoring.yml --ask-vault-pass --tags grafana

# Loki only
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/monitoring.yml --ask-vault-pass --tags loki

# Cert-manager only
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/monitoring.yml --ask-vault-pass --tags cert-manager
```

## Helm values workflow

Application Helm values live in `apps/<component>/values.yml`. ArgoCD in the management
cluster picks up changes to these files automatically when pushed to `main`. To apply a
change:

1. Edit `apps/<component>/values.yml`.
2. Commit and push to `main`.
3. ArgoCD syncs the application automatically (or manually trigger sync in the ArgoCD UI).

For changes that require Kubernetes secrets to be updated (e.g. rotating the Grafana OIDC
client secret), re-run the relevant Ansible role:

```bash
ansible-playbook -i ansible/inventory/monitoring \
  ansible/configurations/monitoring.yml --ask-vault-pass --tags grafana
```

## Kubeconfig

After the Kubernetes role runs, a kubeconfig file is written to the path specified by
`kubeconfig_path` in `vars.yml`. Use it with:

```bash
export KUBECONFIG=<kubeconfig_path>
kubectl get nodes
```

## Environment variables

No environment variables are required at the shell level. All configuration is supplied via
the Ansible vault. The only exception is `KUBECONFIG` if you want to use `kubectl` directly.

## Ansible configuration

`ansible/ansible.cfg` sets:

| Setting | Value | Effect |
|---|---|---|
| `host_key_checking` | `False` | Skips SSH host key prompts (VMs are freshly provisioned) |
| `log_path` | `ansible.log` | Writes a full log to `ansible.log` in the working directory |

## Troubleshooting

### Nodes not joining the cluster

The `kubernetes` role retries the `kubeadm join` command with a back-off. If workers still
fail, check:

- The control-plane node is reachable from workers on the Kubernetes API port.
- The join token has not expired (tokens expire after 24 hours by default); regenerate with
  `kubeadm token create --print-join-command` on the control plane.
- Cloud-init has fully finished on the worker nodes.

### Vault decryption errors

Ensure you are using the same vault password that was used to encrypt the file. If the vault
password file path is configured in `ansible.cfg`, verify it points to the correct file.

### Loki OOM or ingestion errors

Check the resource limits in `apps/alloy/values.yml`. The `alloy-metrics` and `alloy-logs`
components have CPU and memory limits configured. If Alloy is OOMKilled, increase the memory
limit and re-sync via ArgoCD.

### Grafana OIDC login fails

1. Verify the Keycloak OIDC client is configured to allow the Grafana redirect URI.
2. Confirm the `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` in the `grafana-oidc-secret` Kubernetes
   secret matches the Keycloak client secret.
3. Re-run the grafana Ansible role to recreate the secret if it was rotated.

### cert-manager certificate not issued

1. Check cert-manager logs: `kubectl logs -n cert-manager deploy/cert-manager`.
2. Verify the `cloudflare-api-token` secret exists in the `cert-manager` namespace.
3. Confirm the Cloudflare token has `Zone.DNS:Edit` permission for the relevant zone.

### MetalLB IP range conflicts

The MetalLB IP range is set via `metallb_ip_range` in the vault. If services are stuck in
`Pending`, verify no other device on the VLAN is using an IP in that range.
