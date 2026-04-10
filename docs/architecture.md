# Architecture

## Overview

The monitoring cluster is a dedicated Kubernetes cluster that serves as the **centralized observability hub** for the entire andusystems homelab. It collects and visualizes metrics, logs, and traces from all clusters in the environment using the Prometheus + Loki + Tempo + Grafana (LGTM) stack.

## Infrastructure Layers

The cluster is provisioned and configured through three distinct layers:

```
┌─────────────────────────────────────────────────────────┐
│                    Layer 3: Applications                 │
│  Prometheus · Loki · Tempo · Alloy · Grafana · Homepage │
│  Traefik · Cert-Manager · MetalLB · Longhorn · Newt     │
│              (Ansible + Helm charts)                     │
├─────────────────────────────────────────────────────────┤
│                   Layer 2: Kubernetes                    │
│         Flannel CNI · kubeadm · containerd              │
│                    (Ansible)                             │
├─────────────────────────────────────────────────────────┤
│                  Layer 1: Infrastructure                 │
│         Proxmox VMs · Ubuntu cloud images               │
│                   (Terraform)                            │
└─────────────────────────────────────────────────────────┘
```

### Layer 1 — Infrastructure (Terraform)

Terraform provisions virtual machines on Proxmox:

- **Control plane**: Single node with higher CPU/memory allocation
- **Workers**: Multiple worker nodes with larger disk allocations for storage
- **Networking**: Each VM is assigned a static IP on the monitoring VLAN with a shared gateway
- **OS**: Ubuntu cloud images bootstrapped via cloud-init with SSH key injection

### Layer 2 — Kubernetes (Ansible)

Ansible bootstraps a Kubernetes cluster using `kubeadm`:

1. Installs containerd runtime with SystemdCgroup
2. Installs `kubelet`, `kubeadm`, `kubectl` (version-pinned via vault)
3. Configures kernel modules (`overlay`, `br_netfilter`) and sysctl for networking
4. Initializes the control plane with a configured pod CIDR
5. Deploys Flannel CNI for pod networking
6. Joins worker nodes to the cluster

### Layer 3 — Applications (Ansible + Helm)

Applications are deployed via Ansible roles that apply Helm charts and Kubernetes manifests. The deployment order is:

```
MetalLB → Cert-Manager → Pangolin-Newt → Prometheus → Loki → Tempo → Alloy → Homepage → Grafana
```

## Component Diagram

```
                        ┌──────────────────────────────────────────────┐
                        │            External Access                    │
                        │                                              │
                        │   Browser ──► Traefik Ingress ──► Services   │
                        │                    │                         │
                        │          ┌─────────┼──────────┐              │
                        │          ▼         ▼          ▼              │
                        │      Grafana   Prometheus  Homepage          │
                        │                                              │
                        └──────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────────┐
│                          Monitoring Cluster                                   │
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                    │
│  │  Prometheus   │    │     Loki     │    │    Tempo     │                    │
│  │              │    │              │    │              │                    │
│  │ - Metrics    │    │ - Log ingest │    │ - Trace      │                    │
│  │ - Alerting   │    │ - 30d retain │    │   ingest     │                    │
│  │ - 15d retain │    │ - S3 backend │    │ - S3 backend │                    │
│  │ - OTLP recv  │    │   (MinIO)    │    │   (MinIO)    │                    │
│  └──────▲───────┘    └──────▲───────┘    └──────▲───────┘                    │
│         │                   │                   │                            │
│         └───────────────────┼───────────────────┘                            │
│                             │                                                │
│                    ┌────────┴────────┐                                        │
│                    │     Alloy       │                                        │
│                    │                 │                                        │
│                    │ ┌─────────────┐ │                                        │
│                    │ │ alloy-metrics│ │  Collects K8s and node metrics        │
│                    │ ├─────────────┤ │                                        │
│                    │ │ alloy-logs  │ │  Collects pod logs and events          │
│                    │ ├─────────────┤ │                                        │
│                    │ │ alloy-recv  │ │  OTLP receiver (gRPC + HTTP)          │
│                    │ ├─────────────┤ │                                        │
│                    │ │alloy-single │ │  Singleton tasks (cluster events)     │
│                    │ └─────────────┘ │                                        │
│                    └─────────────────┘                                        │
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                    │
│  │   Grafana    │    │   Homepage   │    │ Pangolin-Newt│                    │
│  │              │    │              │    │              │                    │
│  │ - Dashboards │    │ - Service    │    │ - VPN tunnel │                    │
│  │ - SSO (OIDC) │    │   directory  │    │   for admin  │                    │
│  │ - Multi-     │    │ - Quick links│    │   access     │                    │
│  │   cluster    │    │              │    │              │                    │
│  │   datasource │    │              │    │              │                    │
│  └──────────────┘    └──────────────┘    └──────────────┘                    │
│                                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                    │
│  │   Traefik    │    │  Cert-Manager│    │   MetalLB    │                    │
│  │              │    │              │    │              │                    │
│  │ - Ingress    │    │ - Let's      │    │ - L2 load    │                    │
│  │ - TLS term   │    │   Encrypt    │    │   balancer   │                    │
│  │ - HTTP→HTTPS │    │ - DNS-01     │    │ - IP pool    │                    │
│  │   redirect   │    │   (CF)       │    │   mgmt       │                    │
│  └──────────────┘    └──────────────┘    └──────────────┘                    │
│                                                                              │
│  ┌──────────────┐                                                            │
│  │   Longhorn   │                                                            │
│  │              │                                                            │
│  │ - Block PVs  │                                                            │
│  │ - 3 replicas │                                                            │
│  └──────────────┘                                                            │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Data Flows

### Metrics Flow

```
Remote Clusters ──(Prometheus remote read)──► Grafana
                                                 │
Local cluster ──► Alloy (alloy-metrics) ──► Prometheus ──► Grafana
                         │
                    ┌────┴─────┐
                    │ Sources: │
                    │ - node   │
                    │   exporter│
                    │ - kube-  │
                    │   state  │
                    │ - pod    │
                    │   annot. │
                    └──────────┘
```

- **Local metrics**: Alloy scrapes node-exporter, kube-state-metrics, and annotation-autodiscovered pods, then remote-writes to the local Prometheus instance.
- **Cross-cluster metrics**: Grafana connects directly to Prometheus instances on each remote cluster as separate datasources. Each cluster runs its own Prometheus.

### Logs Flow

```
Remote Clusters ──(Loki remote read)──► Grafana
                                           │
Local pods ──► Alloy (alloy-logs) ──► Loki ──► Grafana
                      │
                 Pod logs +
                 Cluster events
```

- **Local logs**: Alloy collects pod logs and Kubernetes events, then pushes to the local Loki instance.
- **Storage**: Loki stores chunks and indexes in MinIO (S3-compatible) on the storage cluster, with 30-day retention.
- **Cross-cluster logs**: Grafana connects directly to Loki instances on each remote cluster.

### Traces Flow

```
Applications ──(OTLP gRPC/HTTP)──► Alloy (alloy-receiver) ──► Tempo
                                                                  │
                                                              Grafana
```

- **Ingestion**: Alloy exposes OTLP receivers (gRPC and HTTP) for application-instrumented traces.
- **Storage**: Tempo stores traces in MinIO on the storage cluster.
- **Metrics generation**: Tempo generates service metrics and remote-writes them back to Prometheus.
- **Cross-cluster traces**: Grafana connects to Tempo instances on each remote cluster.
- **Correlation**: Grafana has `traceToMetrics`, `traceToLogs`, and `correlations` feature toggles enabled for navigating between signals.

### Ingress Flow

```
Internet ──► DNS (Cloudflare) ──► MetalLB VIP ──► Traefik ──► Services
                                                      │
                                               ┌──────┼──────┐
                                               ▼      ▼      ▼
                                           Grafana  Prom  Homepage
```

- **TLS**: Cert-Manager obtains Let's Encrypt certificates using DNS-01 challenges via the Cloudflare API.
- **Routing**: Traefik IngressRoutes map hostnames to backend services with automatic HTTP-to-HTTPS redirection.
- **Load balancing**: MetalLB advertises VIPs using L2 mode for external access.

## Key Design Decisions

### Centralized vs. Federated Monitoring

Grafana acts as the **single pane of glass** by connecting to individual Prometheus, Loki, and Tempo instances on each cluster. This avoids the complexity of federated Prometheus or cross-cluster Alloy pipelines while still providing unified visibility. Each cluster owns its own telemetry data; Grafana simply queries it.

### Alloy Sub-Deployments

Alloy is split into four sub-deployments to separate concerns and resource allocation:

| Sub-deployment | Purpose | Scaling |
|---|---|---|
| `alloy-metrics` | Kubernetes and node metric scraping | DaemonSet-like |
| `alloy-logs` | Pod log and event collection | DaemonSet-like |
| `alloy-receiver` | OTLP ingestion endpoint | Replicated |
| `alloy-singleton` | Cluster-wide singleton tasks | Single replica |

### S3-Backed Storage for Loki and Tempo

Both Loki and Tempo use MinIO (on the storage cluster) as their object storage backend. This separates compute from storage, allows independent scaling, and provides durability beyond the monitoring cluster's local disks.

### Flannel CNI

The cluster uses Flannel for pod networking — a simple, well-understood CNI appropriate for the cluster's scale and requirements.

### Longhorn for Persistent Volumes

Longhorn provides replicated block storage (3 replicas by default) for stateful workloads like Prometheus and Loki, with 200% over-provisioning allowance.

### SSO via Keycloak

Grafana authenticates through Keycloak using OpenID Connect (OIDC), with role mapping for admin, editor, and viewer roles. This integrates with the centralized SSO system used across the environment.

## Resource Allocation

| Component | CPU Request/Limit | Memory Request/Limit |
|---|---|---|
| Prometheus | 200m / 1000m | 512Mi / 2Gi |
| Alertmanager | 50m / 200m | 64Mi / 256Mi |
| Loki | 100m / 1000m | 256Mi / 1Gi |
| Tempo | 100m / 500m | 256Mi / 1Gi |
| Grafana | 100m / 500m | 128Mi / 512Mi |
| Alloy (metrics) | 100m / 500m | 256Mi / 768Mi |
| Alloy (logs) | 50m / 200m | 128Mi / 384Mi |
| Alloy (receiver) | 50m / 250m | 64Mi / 256Mi |
| Alloy (singleton) | 25m / 100m | 32Mi / 128Mi |
| Cert-Manager | 10m / — | 32Mi / — |

## Data Retention

| Store | Retention |
|---|---|
| Prometheus | 15 days |
| Loki | 30 days |
| Tempo | Default (configurable) |

## Persistent Storage Volumes

| Component | Size | StorageClass |
|---|---|---|
| Prometheus | 20Gi | Longhorn |
| Alertmanager | 2Gi | Longhorn |
| Loki | 10Gi | Longhorn |
| Tempo | 10Gi | Longhorn |
| Grafana | 5Gi | Longhorn |
