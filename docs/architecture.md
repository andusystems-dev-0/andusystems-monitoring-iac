# Architecture

## Overview

The andusystems-monitoring repository manages a dedicated monitoring cluster that serves as the centralized observability platform for a multi-cluster homelab environment. The cluster runs on bare-metal Proxmox VMs and hosts a full LGTM stack (Loki, Grafana, Tempo, Prometheus) alongside supporting infrastructure.

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Monitoring Cluster                               │
│                                                                         │
│  ┌─────────────┐     ┌──────────────────────────────────────────────┐  │
│  │   Traefik    │     │           Observability Stack                │  │
│  │  (Ingress)   │     │                                              │  │
│  │             ─┼────►│  ┌────────────┐  ┌───────┐  ┌───────────┐  │  │
│  │  TLS via     │     │  │ Prometheus  │  │ Loki  │  │   Tempo   │  │  │
│  │  Cert-Manager│     │  │ (metrics)   │  │(logs) │  │ (traces)  │  │  │
│  └─────────────┘     │  └─────▲──────┘  └───▲───┘  └─────▲─────┘  │  │
│                       │        │             │             │         │  │
│  ┌─────────────┐     │  ┌─────┴─────────────┴─────────────┴─────┐  │  │
│  │   MetalLB    │     │  │              Grafana Alloy             │  │  │
│  │   (L2 LB)   │     │  │  (unified collector: metrics,         │  │  │
│  └─────────────┘     │  │   logs, traces + OTLP receiver)       │  │  │
│                       │  └───────────────────────────────────────┘  │  │
│  ┌─────────────┐     │                                              │  │
│  │  Longhorn    │     │  ┌────────────────────────────────────────┐ │  │
│  │ (storage)    │     │  │             Grafana                    │ │  │
│  └─────────────┘     │  │  (dashboards, Keycloak SSO,            │ │  │
│                       │  │   multi-cluster datasources)           │ │  │
│  ┌─────────────┐     │  └────────────────────────────────────────┘ │  │
│  │  Homepage    │     └──────────────────────────────────────────────┘  │
│  │ (dashboard)  │                                                       │
│  └─────────────┘     ┌───────────────┐                                 │
│                       │ Pangolin Newt │                                 │
│  ┌─────────────┐     │  (tunnel)     │                                 │
│  │ Cert-Manager│     └───────────────┘                                 │
│  │ (Let's      │                                                       │
│  │  Encrypt)   │                                                       │
│  └─────────────┘                                                       │
└─────────────────────────────────────────────────────────────────────────┘
          ▲                    ▲                    ▲
          │                    │                    │
    ┌─────┴──────┐   ┌────────┴───────┐   ┌───────┴────────┐
    │  Remote     │   │  Remote        │   │  Remote        │
    │  Cluster A  │   │  Cluster B     │   │  Cluster C ... │
    │  (own LGTM) │   │  (own LGTM)   │   │  (own LGTM)   │
    └────────────┘   └────────────────┘   └────────────────┘
```

## Data Flows

### Telemetry Collection (Local)

Grafana Alloy runs as the unified collector within the monitoring cluster, shipping data to three backends:

```
Kubernetes Pods/Nodes
        │
        ▼
  ┌───────────┐
  │   Alloy   │──── metrics ──► Prometheus (remote write)
  │           │──── logs    ──► Loki (push API)
  │           │──── traces  ──► Tempo (OTLP gRPC)
  └───────────┘
```

Alloy collects:
- **Cluster metrics** — node-level and Kubernetes API metrics (delegates to existing node-exporter and kube-state-metrics from kube-prometheus-stack)
- **Pod logs** — aggregated from all namespaces
- **Cluster events** — Kubernetes event stream
- **Application traces** — via OTLP receiver (gRPC and HTTP)
- **Annotation autodiscovery** — scrapes pods with `prometheus.io/*` annotations
- **Prometheus Operator objects** — respects ServiceMonitor and PodMonitor CRDs

### Multi-Cluster Observability

Grafana is configured with datasources pointing to Prometheus, Loki, and Tempo instances running in each remote cluster. Each remote cluster runs its own observability stack; Grafana queries them directly over the network.

```
                    ┌──────────┐
                    │ Grafana  │
                    └────┬─────┘
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │ Management │ │  Storage   │ │ FleetDock  │  ... (+ Networking, local)
   │  Cluster   │ │  Cluster   │ │  Cluster   │
   │ Prom/Loki/ │ │ Prom/Loki/ │ │ Prom/Loki/ │
   │   Tempo    │ │   Tempo    │ │   Tempo    │
   └────────────┘ └────────────┘ └────────────┘
```

This is a **pull-based federation** model — the central Grafana queries each cluster's observability endpoints on demand rather than having data pushed to a central store.

### TLS Certificate Flow

```
Cert-Manager ──► ACME (Let's Encrypt)
     │                    │
     │  DNS-01 challenge  │
     ▼                    ▼
CloudFlare DNS ◄──────────┘
     │
     ▼
TLS Certificates ──► Traefik IngressRoutes
```

All public-facing services use TLS certificates issued by Let's Encrypt via DNS-01 validation against CloudFlare. Cert-Manager automates issuance and renewal.

### Ingress Routing

```
External Request
       │
       ▼
    MetalLB (Layer 2 advertisement)
       │
       ▼
    Traefik (IngressRoute CRDs)
       │
       ├──► Grafana
       ├──► Prometheus
       ├──► Alertmanager
       ├──► Loki
       └──► Homepage
```

Traefik uses IngressRoute custom resources (not standard Ingress) for routing. All routes enforce HTTPS with HTTP-to-HTTPS redirect middleware.

## Storage Architecture

### Persistent Volumes

**Longhorn** serves as the default StorageClass, providing distributed block storage with 3-way replication across worker nodes.

Consumers:
| Component | Volume Size | Purpose |
|---|---|---|
| Prometheus | 20Gi | Metric TSDB (15-day retention) |
| Alertmanager | 2Gi | Alert state |
| Loki | 10Gi | Write-ahead log and local cache |
| Tempo | 10Gi | Write-ahead log and local cache |
| Grafana | 5Gi | Dashboard definitions and settings |

### Object Storage

Loki and Tempo use an external MinIO instance (on a separate storage cluster) as their S3-compatible object store for long-term data:

- **Loki** — stores log chunks and ruler data in dedicated S3 buckets (TSDB schema v13, 30-day retention)
- **Tempo** — stores trace data in a dedicated S3 bucket

## Infrastructure Provisioning

Deployment follows a layered approach orchestrated by Ansible:

```
Layer 0: Ansible Orchestration
       │
       ▼
Layer 1: Terraform (Proxmox VMs)
       │
       ▼
Layer 2: Kubernetes Bootstrap (kubeadm + Flannel)
       │
       ▼
Layer 3: Terraform (Helm Chart Installation)
       │
       ▼
Layer 4: Ansible (Kubernetes Manifests — secrets, CRDs, IngressRoutes)
```

1. **VM Provisioning** — Terraform creates VMs on Proxmox, Ansible configures SSH access
2. **Kubernetes Bootstrap** — kubeadm initializes the control plane, Flannel provides pod networking, workers join the cluster
3. **Helm Charts** — Terraform deploys Helm releases for all applications
4. **Post-install Configuration** — Ansible applies Kubernetes manifests (secrets from vault, CRDs, IngressRoutes)

## Cluster Topology

The monitoring cluster consists of a control plane node and multiple worker nodes. Nodes are provisioned as Proxmox VMs on bare-metal servers with Intel Xeon processors.

- **Control Plane**: Single node running the Kubernetes API server, scheduler, and controller manager
- **Workers**: Multiple nodes running application workloads
- **Networking**: Flannel CNI for pod networking, MetalLB for external service LoadBalancer IPs (Layer 2 mode)

## Key Design Decisions

### Unified Collector (Alloy)

Grafana Alloy replaces separate metric/log/trace collectors with a single agent. It handles Prometheus scraping, log shipping to Loki, and OTLP trace forwarding to Tempo — reducing operational overhead and providing a single configuration point.

### Separate Grafana Deployment

Grafana is deployed independently rather than through the kube-prometheus-stack chart (`grafana.enabled: false`). This allows custom datasource configuration for multi-cluster federation and independent Keycloak OIDC integration.

### DNS-01 TLS Validation

Let's Encrypt certificates use DNS-01 challenges via CloudFlare rather than HTTP-01. This works behind firewalls/NAT without requiring inbound HTTP access to the cluster for certificate validation.

### Centralized SSO

Grafana authenticates via Keycloak (generic OAuth), enabling centralized identity management. Role mapping (`admin`, `editor`, `viewer`) is derived from Keycloak realm roles.

### Longhorn for Persistence

Longhorn provides 3-way replicated block storage across worker nodes, ensuring data survives individual node failures. It serves as the default StorageClass for all stateful workloads.

### Infrastructure as Code

The entire stack — from VMs to application configuration — is defined declaratively. Proxmox VMs are managed by Terraform, Kubernetes is bootstrapped by Ansible, and applications are deployed via Helm with Ansible orchestration. Sensitive values are stored in Ansible Vault.

## Namespace Layout

| Namespace | Components |
|---|---|
| `prometheus` | Prometheus, Alertmanager, Prometheus Operator, node-exporter, kube-state-metrics |
| `loki` | Loki (single binary mode) |
| `tempo` | Tempo |
| `alloy` | Grafana Alloy (metrics, logs, singleton, receiver) |
| `grafana` | Grafana |
| `cert-manager` | Cert-Manager, ClusterIssuer |
| `metallb-system` | MetalLB (controller + speaker) |
| `newt` | Pangolin Newt |
| `kube-system` | Traefik, Flannel, core Kubernetes components |
