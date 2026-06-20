# Course Curriculum Concept Map: Connecting Days 1–29 to Day 30

This document maps the daily learning modules (Days 1–29) to their concrete implementations in this Day 30 capstone project.

---

## 🗺️ Curriculum Mapping

### Phase 1: Foundations (Days 1–9)
*   **Day 1–3: Cluster Architecture & API Server**: Implemented inside `02-cluster/kind-ha-config.yaml` using 3 HA control plane nodes mapping etcd consensus.
*   **Day 4–6: Pod Scheduling & Lifecycle**: Applied inside `09-ai-data-services/k8s-deployment.yaml` defining startup probes, affinity rules, and grace periods.
*   **Day 7–9: Service Discovery & Cluster Networking**: Managed by ClusterIP service endpoints and default CNI IP mapping inside `03-networking/ingress-nginx.yaml`.

### Phase 2: Running Applications (Days 10–15)
*   **Day 10–11: Ingress Routing**: Manifested inside `03-networking/ingress-nginx.yaml` utilizing external mapping via NodePorts.
*   **Day 12–13: cert-manager & TLS Hardening**: Executed inside `03-networking/cert-manager-issuer.yaml` binding ACME solvers for SSL generation.
*   **Day 14–15: Network Policies & Namespace Boundaries**: Configured inside `04-security/network-policies.yaml` executing zero-trust isolation boundaries.

### Phase 3: Observability Stack (Days 16–21)
*   **Day 16–17: Prometheus & ServiceMonitors**: Defined in `05-monitoring/prometheus-rules.yaml` utilizing target discovery rules.
*   **Day 18–19: Loki Logging & LogQL Aggregation**: Configured in `10-observability/loki-promtail.yaml` scraping logs from node runtimes.
*   **Day 20–21: OpenTelemetry Tracing**: Implemented inside `09-ai-data-services/fastapi-app/main.py` routing trace paths to the collector.

### Phase 4: Advanced Engineering (Days 22–27)
*   **Day 22–23: GitOps and ArgoCD Controller**: Programmed in `06-cicd/argo-app.yaml` sync policies.
*   **Day 24–25: Autoscaling (HPA/VPA/Karpenter)**: Specified in `07-autoscaling/` directories dynamically adjusting computes.
*   **Day 26–27: Stateful persistence (PostgreSQL/Kafka)**: Defined in `08-stateful-workloads/` specs with replication properties.

### Phase 5: Production Systems (Days 28–29)
*   **Day 28–29: Chaos Testing & Disaster Recovery**: Managed in `11-testing/chaos-scenarios.yaml` and `12-operations/` failover SOP definitions.
