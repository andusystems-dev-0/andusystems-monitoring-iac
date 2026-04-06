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
                        └──┬───────┬────────┬───────┘
                           │       │        │
              ┌────────────┘       │        └────────────┐
              ▼                    ▼                      ▼
       ┌──────────┐        ┌──────────┐          ┌──────────┐
       │Prometheus │        │   Loki   │          │  Tempo   │
       │  15d ret. │        │ 30d ret. │          │  S3 store│
       │  Longhorn │        │ S3/MinIO │          │  S3/MinIO│
       └─────▲────┘        └────▲─────┘          └────▲─────┘
             │                   │                     │
             │ remote write      │ loki push           │ OTLP gRPC
             │                   │                     │
       ┌─────┴───────────────────┴─────────────────────┴─────┐
       │                   Grafana Alloy                      │
       │                                                      │
       │  alloy-metrics (DaemonSet)                           │
       │    → kubelet, cAdvisor, node-exporter, kube-state    │
       │    → annotation autodiscovery                        │
       │    → ServiceMonitor / PodMonitor support             │
       │                                                      │
       │  alloy-logs (DaemonSet)                              │
       │    → all pod logs → Loki                             │
       │                                                      │
       │  alloy-singleton (Deployment, 1 replica)             │
       │    → Kubernetes events → Loki                        │
       │                                                      │
       │  alloy-receiver (Deployment)                         │
       │    → OTLP gRPC + HTTP receiver                       │
       │    → application instrumentation endpoint            │
       └─────────────────────────────────────────────────────┘
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

All applications are exposed via Traefik IngressRoutes with automatic TLS certificate provisioning through Cert-Manager using Cloudflare DNS01 validation.

### Storage Architecture

```
  ┌───────────────────────────────┐
  │      Persistent Volumes       │
  │                               │
  │  Prometheus ── Longhorn PVC   │
  │  Grafana    ── Longhorn PVC   │
  │  Tempo      ── Longhorn PVC   │
  │  Loki       ── Longhorn PVC   │
  └───────────────────────────────┘

  ┌───────────────────────────────┐
  │     Object Storage (S3)       │
  │                               │
  │  Loki  ──┐                    │
  │           ├── Centralized     │
  │  Tempo ──┘    MinIO (remote)  │
  └───────────────────────────────┘
```

- **Longhorn** provides replicated block storage for persistent volume claims
- **MinIO** is hosted on a separate storage cluster and used as S3-compatible object storage for Loki and Tempo

## Data Flows

### Metrics Pipeline

1. **Alloy metrics DaemonSet** scrapes kubelets, cAdvisor, node-exporter, and kube-state-metrics on every node
2. Alloy respects `prometheus.io/*` annotations for autodiscovery of application metrics
3. Alloy forwards metrics via **remote write** to Prometheus
4. Prometheus stores metrics locally with 15-day retention on Longhorn volumes
5. Prometheus also accepts **OTLP** metrics from Tempo's metrics generator
6. Grafana queries Prometheus for visualization and alerting

### Logging Pipeline

1. **Alloy logs DaemonSet** tails all pod logs on every node
2. **Alloy singleton** collects Kubernetes cluster events
3. Both push logs to **Loki** via the Loki push API
4. Loki stores log data in S3 (MinIO) with 30-day retention, using TSDB index format
5. Grafana queries Loki for log exploration and correlation with traces/metrics

### Tracing Pipeline

1. Applications send traces via **OTLP gRPC/HTTP** to the Alloy receiver
2. Alloy forwards traces to **Tempo** via OTLP gRPC
3. Tempo stores trace data in S3 (MinIO)
4. Tempo's **metrics generator** produces span metrics and pushes them to Prometheus via remote write
5. Grafana queries Tempo and correlates traces with metrics and logs

### Multi-Cluster Monitoring

Grafana is configured with datasources from multiple remote clusters:

- **Local cluster**: Prometheus, Loki, Tempo (in-cluster service endpoints)
- **Remote clusters**: Prometheus, Loki, Tempo (accessed via load balancer IPs)

This enables a single Grafana instance to provide cross-cluster observability.

## Key Design Decisions

### Single-Binary Deployments
Loki and Tempo run in single-binary mode (one replica each). This simplifies operations and is appropriate for the cluster's scale. For higher availability, these could be migrated to microservices mode.

### Centralized Object Storage
Rather than running MinIO per cluster, a centralized MinIO instance on the storage cluster serves as the S3 backend for Loki and Tempo. This reduces operational overhead and centralizes data management.

### Alloy as Unified Collector
Grafana Alloy replaces individual agents (Promtail, Grafana Agent, etc.) with a single, configurable collector that handles metrics, logs, and traces. It runs as:
- **DaemonSets** for node-level metrics and log collection
- **Singleton** for cluster-wide event collection
- **Receiver deployment** for application OTLP instrumentation

### Ansible + Terraform Layered Provisioning
Infrastructure deployment is split into two Terraform layers:
1. **Layer 1**: VM provisioning on Proxmox
2. **Layer 2**: Helm chart deployment on Kubernetes

Ansible orchestrates these layers along with Kubernetes bootstrapping, providing a single command to deploy the entire stack.

### Keycloak OIDC for Grafana
Grafana authenticates users via Keycloak OIDC, with role mapping from JWT claims. This integrates with the broader SSO infrastructure managed on the management cluster.

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
10. Homepage     (Dashboard)
11. Grafana      (Visualization -- last, depends on all datasources)
```

This ordering ensures each component's dependencies are available before it is deployed.

## Cluster Topology

The cluster consists of a single control plane node and multiple worker nodes provisioned as virtual machines on a Proxmox hypervisor. All nodes run within a dedicated monitoring network segment, isolated from other infrastructure VLANs.

MetalLB operates in L2 mode to provide external IP addresses for services, while Traefik handles all ingress routing with TLS termination.
