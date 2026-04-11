# Architecture

## System Overview

The andusystems-monitoring repository deploys a complete observability platform on a dedicated Kubernetes cluster. It serves as the centralized monitoring hub for a multi-cluster homelab environment, aggregating metrics, logs, and traces from all clusters into a single pane of glass.

## Component Diagram

```
                          ┌──────────────────────────────────────────────┐
                          │          External Access (HTTPS)             │
                          │  grafana.<domain> prometheus.<domain> etc.   │
                          └──────────────┬───────────────────────────────┘
                                         │
                                    ┌────▼────┐
                                    │ Traefik │  ◄── TLS termination
                                    │ Ingress │      (Let's Encrypt via
                                    └────┬────┘       Cert-Manager)
                                         │
                          ┌──────────────┼──────────────────┐
                          │              │                  │
                    ┌─────▼─────┐  ┌─────▼──────┐  ┌───────▼───────┐
                    │  Grafana  │  │ Prometheus │  │  AlertManager │
                    │ (SSO/OIDC)│  │  (metrics) │  │   (alerts)    │
                    └─────┬─────┘  └─────┬──────┘  └───────────────┘
                          │              │
          ┌───────────────┼──────────────┼───────────────┐
          │               │              │               │
    ┌─────▼─────┐  ┌──────▼─────┐  ┌────▼────┐  ┌───────▼──────┐
    │   Loki    │  │   Tempo    │  │  Alloy  │  │  kube-state  │
    │  (logs)   │  │  (traces)  │  │(collect)│  │   -metrics   │
    └─────┬─────┘  └──────┬─────┘  └────┬────┘  └──────────────┘
          │               │              │
          │         ┌─────▼─────┐        │
          │         │   MinIO   │        │
          │         │ (storage  │        │
          │         │  cluster) │        │
          │         └───────────┘        │
          │                              │
    ┌─────▼──────────────────────────────▼─────────────────┐
    │                   Longhorn (PVCs)                     │
    │              Distributed Block Storage                │
    └──────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────┐
    │                    MetalLB                            │
    │          L2 Load Balancer (Service IPs)               │
    └──────────────────────────────────────────────────────┘
```

## Data Flows

### Metrics Pipeline

```
  Remote Clusters                    Local Cluster
  ┌───────────┐                     ┌──────────────────┐
  │ Cluster A │──Prometheus──┐      │   Alloy Metrics  │
  │ Cluster B │──Prometheus──┤      │   (DaemonSet)    │
  │ Cluster C │──Prometheus──┤      │    ┌─────────┐   │
  │ Cluster D │──Prometheus──┤      │    │kubelet  │   │
  └───────────┘              │      │    │cAdvisor │   │
                             │      │    │kube-sm  │   │
                             │      │    │node-exp │   │
                             ▼      │    └────┬────┘   │
                         ┌───────┐  │         │        │
                         │Grafana│◄─┤         ▼        │
                         │queries│  │   ┌──────────┐   │
                         └───────┘  │   │Prometheus│◄──┤── remote write
                                    │   │ (local)  │   │
                                    │   └──────────┘   │
                                    └──────────────────┘
```

Grafana is configured with datasources pointing to both the local Prometheus instance and the Prometheus endpoints on every remote cluster. This enables unified dashboards that span the entire infrastructure.

Locally, Alloy runs as a DaemonSet collecting kubelet metrics, cAdvisor container metrics, kube-state-metrics, and node-exporter host metrics. It also discovers and scrapes pods annotated with `prometheus.io/*` annotations and processes Prometheus Operator ServiceMonitors and PodMonitors. All locally collected metrics are forwarded to the local Prometheus via remote write.

### Logging Pipeline

```
  ┌──────────────────────────────────────────┐
  │            All Cluster Nodes              │
  │  ┌─────────────────────────────────────┐  │
  │  │         Alloy Logs (DaemonSet)      │  │
  │  │  ┌──────────┐    ┌──────────────┐   │  │
  │  │  │ Pod Logs │    │ K8s Events   │   │  │
  │  │  │ (stdout/ │    │ (singleton)  │   │  │
  │  │  │  stderr) │    └──────┬───────┘   │  │
  │  │  └────┬─────┘           │           │  │
  │  │       └─────────┬───────┘           │  │
  │  └─────────────────┼──────────────────-┘  │
  └────────────────────┼──────────────────────┘
                       ▼
                 ┌───────────┐
                 │   Loki    │
                 │ (ingester)│
                 └─────┬─────┘
                       │
              ┌────────▼────────┐
              │ MinIO (S3)      │
              │ ┌─────────────┐ │
              │ │  loki-data  │ │  ◄── chunks
              │ │  loki-ruler │ │  ◄── alert rules
              │ └─────────────┘ │
              └─────────────────┘
```

Alloy log collectors run on every node (including control-plane nodes via tolerations) and tail all pod stdout/stderr. A singleton Alloy instance collects Kubernetes cluster events. All logs are pushed to Loki's HTTP push API. Loki stores chunks in MinIO object storage on a separate storage cluster, with a configurable retention period.

Grafana queries Loki instances on both the local and remote clusters for unified log search.

### Tracing Pipeline

```
  ┌─────────────────────────────────┐
  │     Instrumented Applications   │
  │  (OTLP gRPC / HTTP)            │
  └──────────────┬──────────────────┘
                 │
        ┌────────▼────────┐
        │  Alloy Receiver │
        │  (OTLP endpoint)│
        └────────┬────────┘
                 │
           ┌─────▼─────┐
           │   Tempo    │
           │ (ingester) │
           └──┬──────┬──┘
              │      │
    ┌─────────▼┐  ┌──▼──────────┐
    │  MinIO   │  │ Prometheus  │
    │ (S3)     │  │ (span       │
    │tempo-data│  │  metrics)   │
    └──────────┘  └─────────────┘
```

Applications emit traces via OTLP (gRPC or HTTP) to the Alloy receiver, which forwards them to Tempo. Tempo ingests spans, stores them in MinIO, and generates span metrics that are written back to Prometheus via remote write. Grafana connects to Tempo for trace visualization and supports trace-to-metrics and trace-to-logs correlation via feature toggles.

## Key Design Decisions

### Centralized Monitoring Cluster

All observability tooling runs on a dedicated cluster rather than being distributed across workload clusters. This provides:

- **Isolation** — monitoring workloads do not compete for resources with application workloads
- **Survivability** — the monitoring stack remains operational even if a workload cluster fails
- **Unified view** — a single Grafana instance with datasources spanning all clusters

### Alloy as Unified Collector

Grafana Alloy replaces separate Prometheus exporters, Promtail, and OTLP collectors with a single agent. It is deployed in four modes:

| Mode | Deployment | Purpose |
|------|------------|---------|
| `alloy-metrics` | DaemonSet | Kubelet, cAdvisor, kube-state-metrics, node-exporter, annotation autodiscovery |
| `alloy-logs` | DaemonSet | Pod stdout/stderr log collection |
| `alloy-singleton` | Deployment (1 replica) | Kubernetes cluster events |
| `alloy-receiver` | Deployment | OTLP gRPC/HTTP receiver for application traces |

All Alloy instances have tolerations for control-plane nodes to ensure complete coverage.

### S3-Backed Long-Term Storage

Loki and Tempo use MinIO (on the storage cluster) as their object storage backend. This separates compute from storage, allows independent scaling, and provides long-term retention without consuming local disk on the monitoring cluster. Longhorn is used only for working-set PVCs (Prometheus WAL, Loki/Tempo ingester buffers).

### SSO via OIDC

Grafana authenticates users through an external Keycloak identity provider using OpenID Connect. Role mapping is configured so that identity provider groups map to Grafana roles (admin, editor, viewer), eliminating the need for local user management.

### DNS-01 TLS Certificates

Cert-manager uses the Cloudflare DNS-01 ACME challenge solver, which allows issuing wildcard and internal-only certificates without requiring inbound HTTP access from the internet.

### GitOps Deployment Model

The cluster state defined in the `apps/` directory is the source of truth for ArgoCD. A central ArgoCD instance on the management cluster syncs these manifests to the monitoring cluster. Ansible is used for initial bootstrapping (VM provisioning, Kubernetes installation, secret injection) but ongoing state reconciliation is handled by ArgoCD.

## Invariants

- **Secrets are never committed.** All credentials are sourced from Ansible Vault at deploy time and injected as Kubernetes Secrets. Vault example files serve as templates.
- **Longhorn replica count is 3.** All persistent volumes maintain three replicas across worker nodes for data durability.
- **Alloy runs on all nodes.** DaemonSet tolerations ensure metric and log collection includes control-plane nodes.
- **All ingress is HTTPS.** Traefik is configured to redirect HTTP to HTTPS. Certificates are automatically provisioned and renewed.
- **Prometheus scrapes all namespaces.** ServiceMonitor and PodMonitor selectors are not namespace-restricted, ensuring new workloads are automatically discovered.

## Concurrency Model

This repository does not contain application code with concurrent execution. The infrastructure components handle concurrency as follows:

- **Prometheus** — single-instance deployment with a local Longhorn PVC for TSDB. No horizontal scaling; vertical scaling via resource limits.
- **Loki** — deployed in single-binary (monolithic) mode. A single replica handles ingestion and querying. Concurrency is bounded by per-tenant ingestion rate limits and query parallelism settings.
- **Tempo** — single-binary mode with configurable per-tenant trace limits. The metrics generator runs in-process and writes to Prometheus asynchronously.
- **Alloy** — DaemonSet-per-node for metrics and logs ensures each node is handled by exactly one collector. The singleton deployment guarantees only one instance collects cluster events.
- **Ansible playbooks** — executed sequentially (VMs -> Kubernetes -> Apps) with serial task execution within each play.

## Network Architecture

The monitoring cluster operates on a dedicated network segment within the multi-cluster environment. Cross-cluster communication is handled via MetalLB-assigned load balancer IPs:

- Each remote cluster exposes its Prometheus, Loki, and Tempo services via MetalLB
- The monitoring cluster's Grafana reaches these endpoints directly over the internal network
- External user access is routed through Traefik with TLS termination

```
  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
  │ Management  │  │ Networking  │  │  FleetDock  │  │   Storage   │
  │   Cluster   │  │   Cluster   │  │   Cluster   │  │   Cluster   │
  │  Prom/Loki  │  │  Prom/Loki  │  │  Prom/Loki  │  │  Prom/Loki  │
  │   /Tempo    │  │   /Tempo    │  │   /Tempo    │  │   /Tempo    │
  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
         │                │                │                │
         └────────────────┼────────────────┼────────────────┘
                          │                │
                    ┌─────▼────────────────▼─────┐
                    │   Monitoring Cluster        │
                    │   ┌───────────────────────┐ │
                    │   │       Grafana         │ │
                    │   │  (unified dashboards) │ │
                    │   └───────────────────────┘ │
                    └────────────────────────────-┘
```
