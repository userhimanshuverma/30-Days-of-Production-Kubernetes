# Day 23 Daily Assignment: Service Mesh Challenges

## Challenge 1: Implement an 80/20 Canary Split with Circuit Breaking

### Context
Your development team is deploying version `v3.0.0` of a high-throughput transaction backend (`payment-gateway`). This service is highly sensitive; memory leaks or high latency under load could crash transaction processing.

### Objective
Write the complete Kubernetes Deployments (`v2.1.0` and `v3.0.0`), Services, and Istio configuration files (`VirtualService` and `DestinationRule`) that implement the following:
1.  **Traffic Split**: 80% of HTTP traffic directed to subset `stable` (labels `version: v2.1.0`) and 20% to `canary` (labels `version: v3.0.0`).
2.  **Circuit Breaker**: If a pod in the `canary` subset returns 3 consecutive 5xx errors within a 10-second period, it must be ejected from the load-balancer pool for 45 seconds (`consecutive5xxErrors`, `interval`, `baseEjectionTime`).
3.  **Connection Limit**: Limit the `canary` cluster to a maximum of 50 concurrent TCP connections and 5 pending HTTP requests.

---

## Challenge 2: Secure Multi-Namespace Workload Isolation

### Context
Your organization runs a multi-tenant cluster. The namespaces are:
*   `frontend` (contains public web apps)
*   `billing` (contains sensitive payment APIs)
*   `analytics` (contains background reporting tools)

An security audit requires that the `billing` services are isolated.

### Objective
Write an `AuthorizationPolicy` manifest for the `billing` namespace that:
1.  Enforces zero-trust: Blocks all traffic to workloads in the `billing` namespace by default.
2.  Whitelist: Only permits workloads in the `frontend` namespace running with the service account `frontend-sa` to execute HTTP `POST` requests on the path `/payments/charge`.
3.  Block Analytics: Workloads in the `analytics` namespace (even with sidecars) must be completely forbidden from calling the billing services.

---

## Challenge 3: Exclude Ports from Sidecar Interception

### Context
Your application uses a third-party metrics daemon that pulls logging info from local container processes. However, when sidecar injection is enabled, the metrics collector loses connection because the proxy intercepts its telemetry calls and validates them against mTLS policies.

### Objective
1.  Determine which annotation tells Istio to bypass sidecar interception for specific inbound and outbound ports.
2.  Modify the Pod Spec of a sample deployment to exclude inbound port `9090` and outbound port `2181` (Zookeeper) from the proxy capture.
3.  Validate your setup using a local Kind cluster and check if communication on these ports bypasses Envoy.
