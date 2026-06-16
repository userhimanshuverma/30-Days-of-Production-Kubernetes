# 📝 Deep Dive: Core Concepts in Multi-Cluster Kubernetes

This document provides a rigorous technical breakdown of the concepts, mechanisms, and architectural designs used to scale Kubernetes beyond a single cluster.

---

## ⚡ 1. Control Plane Topologies: Split vs. Shared

When deploying workloads across multiple clusters, you must choose how control planes are managed and isolated:

### A. Shared Control Plane (Single-Cluster Multi-Region Node Pools)
In this layout, a single logical Kubernetes control plane (API server, Scheduler, Controller Manager) manages worker nodes located in different physical regions or zones.
*   **How it works**: The master nodes reside in a central region (e.g., `us-east-1`). Worker nodes are deployed in both `us-east-1` and `us-west-2`, connecting back to the central API server over WAN or DirectConnect.
*   **Pros**:
    *   Single API endpoint to manage.
    *   Simplified resource deployment; you apply a Deployment once, and it schedules pods across zones/regions.
*   **Cons**:
    *   **Blast Radius**: If the central control plane fails, node registration fails globally.
    *   **Latency & Disconnection**: If the network link between `us-west-2` and `us-east-1` breaks (split-brain or WAN partition), the master cannot poll the status of nodes in `us-west-2`. The master scheduler will assume those nodes are dead, mark them as `Unreachable`, and attempt to reschedule all workloads to `us-east-1`, creating a massive resource starvation event.
    *   **High etcd Latency**: etcd requires low write latency (< 10ms). Distributing etcd members across WAN regions triggers consensus election timeouts, degrading performance.

### B. Split Control Plane (Multi-Cluster Model)
In this layout, each physical location runs a completely autonomous and independent Kubernetes cluster with its own control plane, etcd database, and API server.
*   **How it works**: `Cluster-East` runs in `us-east-1` and `Cluster-West` runs in `us-west-2`. They have no direct dependency on one another.
*   **Pros**:
    *   **Fault Isolation**: If `Cluster-East` fails completely or its API server gets overwhelmed, `Cluster-West` continues to run and serve traffic normally.
    *   **Local Low Latency**: API writes are executed locally in each region, avoiding long-distance etcd replication over WAN.
    *   **No Split-Brain Ingress**: If WAN splits, clusters operate autonomously with zero service disruption to local users.
*   **Cons**:
    *   **Operational Sprawl**: You must maintain separate kubeconfigs, RBAC rules, monitoring pipelines, and upgrade cycles.
    *   **Sync Requirements**: Workloads must be synchronized manually or via GitOps / Federation controllers across all clusters.

---

## 🏗️ 2. Cluster Federation Mechanics

Federation coordinates resource configuration across independent clusters without merging their control planes.

```
       [ Client / GitOps Pipeline ]
                   │
                   ▼
       +───────────────────────+
       |   Federation Hub      |
       |  (e.g., Karmada, OCM) |
       +───────────────────────+
                   │
         Match Propagation Rules
                   │
         ┌─────────┴─────────┐
         ▼                   ▼
+────────────────+  +────────────────+
| Spoke Cluster  |  | Spoke Cluster  |
|     (East)     |  |     (West)     |
|                |  |                |
|  [Override A]  |  |  [Override B]  |
+────────────────+  +────────────────+
```

### The Three Pillars of Federated API Objects:
1.  **Resource Template**: The standard, raw Kubernetes resource (e.g., a Deployment without cluster-specific configurations).
2.  **Propagation Policy**: A set of rules that defines which spoke clusters receive the resource. It controls scheduling criteria:
    *   *Duplicated*: Every cluster gets the identical resource.
    *   *Aggregated (Divided)*: Replicas are split dynamically based on cluster weight or resource capacity (e.g., total replicas = 10; 7 to Cluster-A, 3 to Cluster-B).
    *   *Failover-based*: Run in Cluster-A, shift to Cluster-B if Cluster-A becomes unhealthy.
3.  **Override Policy**: A transformation matrix that intercepts the Resource Template and applies specific JSON patches before injecting it into the target cluster.
    *   *Example*: Modifying the database host string to point to the local RDS read-replica, or adding region-specific environment variables.

---

## 🔗 3. Cross-Cluster Networking & Service Discovery

For pods in different clusters to communicate, the network layer must support cross-cluster routing.

### A. Flat Network Overlays (Direct Pod-to-Pod Routing)
Traditionally, Kubernetes assumes pod IPs are only routable within a single cluster. Flat networking bridges this, ensuring pod IPs are unique across all connected clusters and routing packets directly.

#### Cilium ClusterMesh (eBPF-powered Routing)
*   **Under the Hood**: Cilium uses eBPF to route packets directly. When you connect clusters using ClusterMesh:
    1.  The Cilium agents in each cluster connect directly to the etcd / apiserver of the other cluster to sync pod IP allocations and service endpoints.
    2.  Network packets are routed either natively (via BGP routing tables) or encapsulated (via VXLAN or Geneve tunnels) across cluster boundaries.
    3.  Because Cilium operates at the socket layer via eBPF, it bypasses the iptables overhead, maintaining high throughput and low CPU cost.
*   **Prerequisite**: The Pod IP CIDR ranges of all participating clusters **must not overlap**. If `Cluster-A` and `Cluster-B` both assign `10.244.0.0/16` to pods, direct routing is impossible.

#### Submariner (IPsec/WireGuard Tunnels)
*   **Under the Hood**: Submariner deploys a Gateway engine on designated nodes in each cluster.
    1.  It establishes encrypted IPsec or WireGuard VPN tunnels between the gateways.
    2.  It monitors cross-cluster traffic and routes packets destined for remote pod CIDRs through the tunnels.
    3.  It supports **Globalnet**, which uses Network Address Translation (NAT) to connect clusters even if they have **overlapping Pod IP CIDRs**.

### B. Service Export and Import (Multi-Cluster Services - MCS)
The Kubernetes Multi-Cluster Services API (KEP-1645) standardizes cross-cluster service discovery:
*   `ServiceExport`: When you apply this resource in `Cluster-A` for a service named `frontend`, it instructs the cluster mesh to share its endpoints.
*   `ServiceImport`: The mesh control plane automatically generates a corresponding virtual service in `Cluster-B`. Pods in `Cluster-B` can then access the remote endpoints using the DNS name:
    `frontend.default.svc.clusterset.local`

---

## 🌐 4. Global Traffic Routing (GSLB & Anycast)

Once services are running across multiple regional clusters, you must route end-users to the optimal cluster.

```
                  [ User Request ]
                         │
              +────────────────────+
              |     Global DNS     | (Resolves to nearest cluster IP)
              +────────────────────+
                         │
             ┌───────────┴───────────┐
             ▼                       ▼
      [ Ingress East ]        [ Ingress West ]
     (192.0.2.10: Anycast)   (198.51.100.20: Anycast)
             │                       │
             ▼                       ▼
      [ Cluster East ]        [ Cluster West ]
```

### A. GeoDNS (Geography-based Routing)
*   The DNS server (e.g., Route53, Cloudflare DNS, or CoreDNS with GeoIP plugin) checks the client's DNS resolver IP.
*   It looks up the country/region of the client in a database (like MaxMind GeoIP).
*   It responds with the IP address of the load balancer closest to that region.
*   **Limitation**: DNS caching. If an ISP resolver caches a DNS query, users may continue to be routed to a degraded region until the Time-to-Live (TTL) expires (often 60 to 300 seconds).

### B. Anycast IP Routing (Network-layer Steering)
*   You assign the exact same IP address to the Load Balancer endpoints in both US, Europe, and Asia.
*   Using BGP, these routers advertise ownership of this IP to the global Internet.
*   The internet routing protocol automatically routes packets along the shortest network path (lowest AS path length) to the nearest entry point.
*   **Advantage**: Immediate failover. If the ingress router in the US goes offline, BGP routes withdraw, and the next closest path (e.g., Europe) instantly inherits the traffic without waiting for DNS cache expiration.

---

## 🔄 5. Disaster Recovery Architectures

Resilience is designed along a spectrum of recovery speeds and costs:

| Architecture | Description | RTO (Recovery Time Objective) | RPO (Recovery Point Objective) | Cost Factor |
| :--- | :--- | :--- | :--- | :--- |
| **Active-Active** | Workloads actively process transactions in both regions. Multi-region database (e.g. CockroachDB) replicates state synchronously. | < 1 minute (Instant redirect) | 0 (Synchronous replication) | High (Double resources + DB licenses) |
| **Active-Passive (Warm Standby)** | Passive region runs a scaled-down version of the app. Databases sync asynchronously. | 5 - 15 minutes (Scale-up + DNS change) | Near-zero to few minutes (Async lag) | Medium (Idle resources run at low cost) |
| **Active-Passive (Cold Standby)** | Passive region is offline. Workload manifests are stored in Git. Database backups are written to S3. | Hours (Create cluster, restore data) | Hours (Time of last backup) | Low (Only pay for storage backups) |

*Next: Explore detailed topologies in [diagrams/README.md](../diagrams/README.md) to visualize these concepts.*
