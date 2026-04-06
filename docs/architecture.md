# Architecture

## System Overview

The monitoring cluster runs a Kubernetes-based observability platform that collects and visualizes metrics, logs, and traces from itself and from remote clusters across the infrastructure.

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Monitoring Cluster (Kubernetes)                  │
│                                                                     │
│  ┌───────────┐   ┌───────────┐   ┌───────────┐   ┌─────────────┐  │
│  │ Prometheus │   │   Loki    │   │   Tempo   │   │   Grafana   │  │
│  │ (Metrics)  │   │  (Logs)   │   │ (Traces)  │   │   (Viz)     │  │
│  └─────▲─────┘   └─────▲─────┘   └─────▲─────┘   └──────┬──────┘  │
│        │               │               │           reads │from all  │
│        │               │               │                 ▼          │
│  ┌─────┴───────────────┴───────────────┴─────────────────────────┐  │
│  │                     Grafana Alloy                             │  │
│  │  (DaemonSets: metrics + logs | Singleton: events | Receiver) │  │
│  └───────────────────────▲───────────────────────────────────────┘  │
│                          │ scrape / collect                         │
│  ┌───────────────────────┴───────────────────────────────────────┐  │
│  │  Kubernetes Workloads, Kubelets, Node Exporters, cAdvisor     │  │
│  └───────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌──────────────────┐  │
│  │ Traefik  │  │ MetalLB  │  │Cert-Manager│  │    Longhorn      │  │
│  │ (Ingress)│  │  (L2 LB) │  │   (TLS)   │  │   (Storage)      │  │
│  └──────────┘  └──────────┘  └───────────┘  └──────────────────┘  │
│                                                                     │
│  ┌──────────┐  ┌──────────────┐                                    │
│  │ Homepage │  │ Pangolin-Newt│                                    │
│  │(Dashboard)│  │    (VPN)     │                                    │
│  └──────────┘  └──────────────┘                                    │
└─────────────────────────────────────────────────────────────────────┘
         ▲                    ▲                    ▲
         │ remote write       │ remote push        │ OTLP
         │ (metrics)          │ (logs)             │ (traces)
┌────────┴──────┐   ┌────────┴──────┐   ┌────────┴──────┐
│ Remote Cluster│   │ Remote Cluster│   │ Remote Cluster│
│   (Alloy)     │   │   (Alloy)     │   │   (Alloy)     │
└───────────────┘   └───────────────┘   └───────────────┘
```

## Component Diagram

### Observability Stack (LGTM)

```
                        ┌──────────────────────────┐
                        │        Grafana            │
                        │  - Local datasources      │
                        │  - Remote datasources     │
                        │  - Keycloak OIDC SSO      │
                        │  - Trace correlation       │
                        └──┬───────┬────────┬───────┘
                           │       │        │
              ┌────────────┘       │        └────────────┐
              ▼                    ▼                      ▼
       ┌──────────┐        ┌──────────┐          ┌──────────┐
       │Prometheus │        │   Loki   │          │  Tempo   │
       │  15d ret. │        │ 30d ret. │          │  S3 store│
       │  Longhorn │        │ S3/MinIO │          │  S3/MinIO│
       │  OTLP rx  │        │  TSDB    │          │ metrics  │
       └─────▲────┘        └────▲─────┘          └──gen─▲───┘
             │                   │                  │    │
             │ remote write      │ loki push        │    │ OTLP gRPC
             │◄──────────────────┼──────────────────┘    │
             │                   │                       │
       ┌─────┴───────────────────┴───────────────────────┴─────┐
       │                   Grafana Alloy                        │
       │                                                        │
       │  alloy-metrics (DaemonSet)                             │
       │    → kubelet, cAdvisor, node-exporter, kube-state      │
       │    → annotation autodiscovery                          │
       │    → ServiceMonitor / PodMonitor support               │
       │                                                        │
       │  alloy-logs (DaemonSet)                                │
       │    → all pod logs → Loki                               │
       │                                                        │
       │  alloy-singleton (Deployment, 1 replica)               │
       │    → Kubernetes events → Loki                          │
       │                                                        │
       │  alloy-receiver (Deployment)                           │
       │    → OTLP gRPC + HTTP receiver                         │
       │    → application instrumentation endpoint              │
       └───────────────────────────────────────────────────────┘
```

### Networking and Ingress

```
  External Traffic
        │
        ▼
  ┌──────────┐     ┌───────────────┐     ┌──────────────────┐
  │ MetalLB  │────▶│    Traefik    │────▶│  IngressRoutes   │
  │ (L2 LB)  │     │   (Ingress)   │     │  per application │
  └──────────┘     └───────┬───────┘     └──────────────────┘
                           │
                    ┌──────┴──────┐
                    │ Cert-Manager│
                    │ (Let's Encrypt
                    │  + Cloudflare
                    │  DNS01)     │
                    └─────────────┘
```

All applications are exposed via Traefik IngressRoutes with automatic TLS certificate provisioning through Cert-Manager using Cloudflare DNS01 validation. Traefik is configured with CRD-based providers and cross-namespace routing support, enabling IngressRoutes in any namespace to reference services across the cluster.

### Storage Architecture

```
  ┌───────────────────────────────────┐
  │      Persistent Volumes           │
  │      (Longhorn, 3x replication)   │
  │                                   │
  │  Prometheus ── 20Gi Longhorn PVC  │
  │  Grafana    ──  5Gi Longhorn PVC  │
  │  Tempo      ── 10Gi Longhorn PVC  │
  │  Loki       ── 10Gi Longhorn PVC  │
  │  AlertManager── 2Gi Longhorn PVC  │
  └───────────────────────────────────┘

  ┌───────────────────────────────────┐
  │     Object Storage (S3)           │
  │     (Centralized MinIO)           │
  │                                   │
  │  Loki  ──┐                        │
  │           ├── Remote MinIO on     │
  │  Tempo ──┘    storage cluster     │
  │                                   │
  │  Buckets: loki-data, loki-ruler,  │
  │           tempo-data              │
  └───────────────────────────────────┘
```

- **Longhorn** provides replicated block storage (3 replicas, 200% over-provisioning) for persistent volume claims
- **MinIO** is hosted on a separate storage cluster and used as S3-compatible object storage for Loki and Tempo

## Data Flows

### Metrics Pipeline

1. **Alloy metrics DaemonSet** scrapes kubelets, cAdvisor, node-exporter, and kube-state-metrics on every node (tolerates control plane taints)
2. Alloy respects `prometheus.io/*` annotations for autodiscovery of application metrics
3. Alloy honors ServiceMonitor and PodMonitor CRDs from the Prometheus Operator
4. Alloy forwards metrics via **remote write** to Prometheus
5. Prometheus stores metrics locally with **15-day retention** on Longhorn volumes
6. Prometheus also accepts **OTLP** metrics from Tempo's metrics generator (span metrics)
7. Prometheus accepts metrics from remote clusters via its remote write receiver
8. Grafana queries Prometheus for visualization and alerting

### Logging Pipeline

1. **Alloy logs DaemonSet** tails all pod logs on every node (tolerates control plane taints)
2. **Alloy singleton** collects Kubernetes cluster events
3. Both push logs to **Loki** via the Loki push API
4. Loki stores log data in S3 (MinIO) with **30-day retention**, using TSDB index format with 24-hour index periods
5. Loki runs in single-binary mode with configurable ingestion rate limits
6. Grafana queries Loki for log exploration and correlation with traces/metrics

### Tracing Pipeline

1. Applications send traces via **OTLP gRPC/HTTP** to the Alloy receiver
2. Alloy forwards traces to **Tempo** via OTLP gRPC
3. Tempo stores trace data in S3 (MinIO)
4. Tempo's **metrics generator** produces span metrics and pushes them to Prometheus via remote write
5. Grafana queries Tempo and correlates traces with metrics and logs using trace-to-metrics and trace-to-logs features

### Multi-Cluster Monitoring

Grafana is configured with datasources from multiple remote clusters, enabling cross-cluster observability from a single instance:

| Cluster | Datasources |
|---------|-------------|
| Monitoring (local) | Prometheus, Loki, Tempo (in-cluster service endpoints) |
| Management | Prometheus, Loki, Tempo (via load balancer) |
| Storage | Prometheus, Loki, Tempo (via load balancer) |
| Networking | Prometheus, Loki, Tempo (via load balancer) |
| FleetDock | Prometheus, Loki, Tempo (via load balancer) |

Each remote cluster's Tempo datasource is configured with trace-to-metrics and trace-to-logs correlation, linking back to that cluster's Prometheus and Loki instances.

## Resource Allocation

| Component | CPU Request | CPU Limit | Memory Request | Memory Limit |
|-----------|------------|-----------|---------------|-------------|
| Prometheus | 200m | 1000m | 512Mi | 2Gi |
| AlertManager | 50m | 200m | 64Mi | 256Mi |
| Prometheus Operator | 100m | 200m | 128Mi | 256Mi |
| Loki | 100m | 1000m | 256Mi | 1Gi |
| Tempo | 100m | 500m | 256Mi | 1Gi |
| Grafana | 100m | 500m | 128Mi | 512Mi |
| Alloy metrics (per node) | 100m | 500m | 256Mi | 768Mi |
| Alloy logs (per node) | 50m | 200m | 128Mi | 384Mi |
| Alloy singleton | 25m | 100m | 32Mi | 128Mi |
| Alloy receiver | 50m | 250m | 64Mi | 256Mi |

## Key Design Decisions

### Single-Binary Deployments

Loki and Tempo run in single-binary mode (one replica each). This simplifies operations and is appropriate for the cluster's scale. Distributed components (backend, read, write replicas) are explicitly disabled. For higher availability, these could be migrated to microservices mode.

### Centralized Object Storage

Rather than running MinIO per cluster, a centralized MinIO instance on the storage cluster serves as the S3 backend for Loki and Tempo. This reduces operational overhead and centralizes data management. Credentials are injected via Kubernetes secrets.

### Alloy as Unified Collector

Grafana Alloy replaces individual agents (Promtail, Grafana Agent, etc.) with a single, configurable collector that handles metrics, logs, and traces. It runs as:
- **DaemonSets** for node-level metrics and log collection (with control plane tolerations)
- **Singleton** for cluster-wide event collection
- **Receiver deployment** for application OTLP instrumentation (gRPC and HTTP)

### Ansible + Terraform Layered Provisioning

Infrastructure deployment is split into two Terraform layers:
1. **Layer 1**: VM provisioning on Proxmox
2. **Layer 2**: Helm chart deployment on Kubernetes (MetalLB)

Ansible orchestrates these layers along with Kubernetes bootstrapping and application deployment, providing a single command to deploy the entire stack.

### Keycloak OIDC for Grafana

Grafana authenticates users via Keycloak OIDC, with role mapping from JWT claims (`admin` -> Admin, `editor` -> Editor, default -> Viewer). This integrates with the broader SSO infrastructure managed on the management cluster. The OIDC client secret is injected via a Kubernetes secret.

### Prometheus Operator CRDs

The kube-prometheus-stack deploys Prometheus Operator CRDs (ServiceMonitor, PodMonitor, PrometheusRule, etc.) which Alloy honors for service discovery. Prometheus is configured to scrape all namespaces regardless of Helm values, ensuring complete cluster coverage.

### TLS with Cert-Manager

Cert-Manager provisions Let's Encrypt certificates using Cloudflare DNS01 challenges. A single ClusterIssuer serves all IngressRoutes. Each application that requires HTTPS has a Certificate resource referencing this issuer.

## Deployment Order

The Ansible playbook enforces the following deployment sequence:

```
 1. VMs           (Terraform layer 1 -- provision Proxmox VMs)
 2. Kubernetes    (kubeadm init, join workers, install Flannel CNI)
 3. MetalLB       (Terraform layer 2 -- L2 load balancer)
 4. Cert-Manager  (TLS certificate automation)
 5. Pangolin-Newt (VPN access)
 6. Prometheus    (CRDs + kube-prometheus-stack)
 7. Loki          (Log aggregation)
 8. Tempo         (Distributed tracing)
 9. Alloy         (Unified telemetry collection)
10. Homepage      (Dashboard)
11. Grafana       (Visualization -- last, depends on all datasources)
```

This ordering ensures each component's dependencies are available before it is deployed. Notably, Grafana is deployed last because it references all other observability backends as datasources.

## Cluster Topology

The cluster consists of a single control plane node and multiple worker nodes provisioned as virtual machines on a Proxmox hypervisor. All nodes run within a dedicated monitoring network segment, isolated from other infrastructure VLANs.

MetalLB operates in L2 mode to provide external IP addresses for services, while Traefik handles all ingress routing with TLS termination. The cluster uses Flannel as its CNI plugin with a dedicated pod network CIDR.
