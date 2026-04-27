# Architecture

This document describes the component topology, data flows, and key design decisions for the
andusystems monitoring cluster.

## Cluster topology

```
┌──────────────────────────────────────────────────────────────────┐
│                    Monitoring Cluster (VLAN 50)                   │
│                                                                  │
│  ┌─────────────────┐   ┌──────────────────────────────────────┐  │
│  │  Control Plane  │   │           Worker Nodes               │  │
│  │  (monitoringctrl)│  │  monitoringwrkr0 … monitoringwrkr3   │  │
│  └────────┬────────┘   └──────────────┬───────────────────────┘  │
│           │  Flannel CNI overlay       │                          │
│           └────────────┬──────────────┘                          │
│                        │                                         │
│  ┌─────────────────────▼──────────────────────────────────────┐  │
│  │                  Kubernetes Control Plane                   │  │
│  │    kube-apiserver · etcd · scheduler · controller-manager  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │ MetalLB  │  │  Traefik │  │cert-mgr  │  │  Pangolin/   │    │
│  │ (L2 LB)  │  │ (ingress)│  │(TLS/ACME)│  │  Newt (VPN)  │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────┘    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    Observability Stack                      │  │
│  │  ┌──────────────────┐  ┌──────────┐  ┌──────────────────┐ │  │
│  │  │ kube-prometheus- │  │   Loki   │  │     Tempo        │ │  │
│  │  │ stack (Prometheus│  │  (logs)  │  │    (traces)      │ │  │
│  │  │  + Alertmanager) │  └────┬─────┘  └────────┬─────────┘ │  │
│  │  └────────┬─────────┘       │                  │           │  │
│  │           │                 │                  │           │  │
│  │  ┌────────▼─────────────────▼──────────────────▼─────────┐ │  │
│  │  │                    Grafana                             │ │  │
│  │  │     OIDC auth via Keycloak · multi-cluster datasources │ │  │
│  │  └────────────────────────────────────────────────────────┘ │  │
│  │  ┌────────────────────────────────────────────────────────┐ │  │
│  │  │              Grafana Alloy (collector)                  │ │  │
│  │  │  alloy-metrics · alloy-logs · alloy-singleton ·        │ │  │
│  │  │  alloy-receiver (OTLP gRPC + HTTP)                     │ │  │
│  │  └────────────────────────────────────────────────────────┘ │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────┐  ┌──────────────────────────────────────────────┐  │
│  │ Homepage │  │            cluster-status                    │  │
│  │(dashboard│  │  (nginx health endpoint for ArgoCD probing)  │  │
│  └──────────┘  └──────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Data flows

### Metrics

```
Other clusters
  └─▶ Alloy (alloy-metrics)
        └─▶ Prometheus (kube-prometheus-stack)
              └─▶ Grafana datasource (per-cluster Prometheus URL)
```

Alloy runs in four sub-charts:

| Sub-chart | Role |
|---|---|
| `alloy-metrics` | Scrapes cluster metrics; forwards to Prometheus |
| `alloy-logs` | Collects pod logs via Kubernetes API; ships to Loki |
| `alloy-singleton` | Collects cluster-level events (single replica) |
| `alloy-receiver` | Exposes OTLP gRPC and HTTP endpoints for application traces/metrics |

Prometheus Operator objects (ServiceMonitor, PodMonitor) are recognized by Alloy through the
`prometheusOperatorObjects` feature, allowing existing Prometheus-ecosystem configurations to
work without changes.

### Logs

```
Pod stdout/stderr
  └─▶ Alloy (alloy-logs) — Kubernetes API log collection
        └─▶ Loki (single-binary mode)
              └─▶ MinIO (S3 buckets: loki-data, loki-ruler)
```

Loki operates in single-binary mode with a TSDB v13 schema, 24-hour index periods, and
30-day retention. Ingestion limits are set at the role level to avoid resource exhaustion.
Other clusters ship their Loki data to the monitoring cluster's Loki endpoint.

### Traces

```
Applications (OTLP/gRPC or HTTP)
  └─▶ Alloy (alloy-receiver, OTLP endpoints)
        └─▶ Tempo
              └─▶ Grafana datasource (trace → log / trace → metric correlations)
```

### TLS and ingress

```
Let's Encrypt ACME (DNS-01)
  └─▶ cert-manager (Cloudflare DNS-01 solver)
        └─▶ Certificates stored as Kubernetes secrets
              └─▶ Traefik IngressRoute (HTTPS termination)
```

Traefik is deployed separately (managed by andusystems-management). All IngressRoute and
Certificate manifests in `apps/*/manifest.yml` are applied either by Ansible (cert-manager
role) or by ArgoCD in the management cluster.

### Cross-cluster datasources

Grafana is configured with datasources for each cluster in the homelab:

| Cluster | Signal types |
|---|---|
| Monitoring (local) | Prometheus, Loki, Tempo (with service map) |
| Management | Prometheus, Loki, Tempo |
| Storage | Prometheus, Loki, Tempo |
| Networking | Prometheus, Loki, Tempo |
| FleetDock | Prometheus, Loki, Tempo |

Datasource URLs point to each cluster's Prometheus, Loki, and Tempo service endpoints over
the Pangolin VPN tunnel.

## Key design decisions

### Single-binary Loki
Loki runs in single-binary mode (one replica) rather than distributed mode. This trades
horizontal write/read scalability for operational simplicity appropriate for a homelab. The
MinIO S3 backend keeps storage decoupled from the Loki pod.

### ArgoCD split responsibility
Ansible roles handle namespace creation and pre-requisite secrets (credentials, API tokens).
ArgoCD in the management cluster handles Helm chart deployment from `apps/` via GitOps. This
separation ensures secrets are never committed to git while keeping the desired application
state declarative.

### Flannel CNI
The cluster uses Flannel as the CNI plugin. It is lightweight and sufficient for a monitoring
workload that does not require NetworkPolicy enforcement or advanced routing.

### MetalLB L2 mode
MetalLB operates in Layer-2 mode, advertising a dedicated IP range for LoadBalancer services.
This avoids the need for a BGP-capable router in the homelab environment.

### Cert-Manager with Cloudflare DNS-01
DNS-01 challenge is used instead of HTTP-01 because some services are not directly reachable
from the public internet. Cloudflare acts as the DNS provider; the API token is stored as a
Kubernetes secret created by the cert-manager Ansible role.

### Keycloak OIDC for Grafana
Grafana delegates authentication to Keycloak (hosted in the management cluster) via the
generic OAuth/OIDC provider. Role mapping is done via Keycloak groups, so access control is
centralized. The OIDC client secret is injected as a Kubernetes secret by Ansible, not stored
in Helm values.

### Alloy as the unified collector
Grafana Alloy (formerly the Grafana Agent) consolidates scraping, log collection, and trace
reception into a single collector deployment. The annotation autodiscovery and Prometheus
Operator object features allow existing scrape configs to work without migrating to
Alloy-native syntax.

## Invariants

- No sensitive values (credentials, tokens) are stored in any file committed to this
  repository. All secrets are injected at deploy time via Ansible Vault and written to
  Kubernetes secrets.
- Every public-facing service has a Let's Encrypt TLS certificate managed by cert-manager.
- Grafana datasources are configured declaratively in `apps/grafana/values.yml`; manual
  datasource additions are not persisted.
- Loki and Tempo data persists in MinIO, not in pod-local storage, so pod restarts do not
  cause data loss.
