# 🏛️ Multi-Zone & High Availability Architectures

This document details the architectural blueprints for running production-grade, highly available Kubernetes control planes and workloads across multiple physical locations (Availability Zones).

---

## 1. Control Plane Topology: Stacked vs. External etcd

When designing a control plane, you must choose between two distinct topologies for **etcd**:

### Option A: Stacked etcd Topology (Default & Simplest)
In this model, the etcd members run as static pods managed by the kubelet on the same nodes as the control plane components (`kube-apiserver`, `kube-scheduler`, `kube-controller-manager`).

```
+-------------------------------------------------------------+
| Control Plane Node 1    Control Plane Node 2                |
| +-----------------+     +-----------------+                 |
| | kube-apiserver  |     | kube-apiserver  |                 |
| |       |         |     |       |         |                 |
| |     etcd        |     |     etcd        |                 |
| +-------+---------+     +-------+---------+                 |
+---------+-----------------------+---------------------------+
          |                       |
          +------- Raft Quorum ---+
```

* **Pros**:
  - Extremely easy to set up and manage via `kubeadm`.
  - Simpler networking; api-server communicates with local etcd loopback.
  - Fewer servers to provision and pay for.
* **Cons**:
  - Coupled scaling. A resource-intensive api-server query can starve etcd of CPU/IO, leading to Raft election timeouts and cluster instability.
  - Risk of double-failures. If Node 1 crashes, you lose both an api-server instance and an etcd member.

### Option B: External etcd Topology (Recommended for Large Scale)
In this model, etcd members run on a separate dedicated pool of nodes, detached from the `kube-apiserver`.

```
+----------------------+     +----------------------+
| Control Plane Node 1 |     | Control Plane Node 2 |
|  +----------------+  |     |  +----------------+  |
|  | kube-apiserver |  |     |  | kube-apiserver |  |
|  +--------+-------+  |     |  +--------+-------+  |
+-----------|----------+     +-----------|----------+
            +-----------+  +-------------+
                        |  |
                 +------+--+------+
                 | etcd Cluster   |
                 | (Dedicated)    |
                 +----------------+
```

* **Pros**:
  - Isolated resource usage. etcd performance is shielded from api-server workloads.
  - Decoupled lifecycle. You can upgrade, scale, or restore etcd independently of the control plane.
  - Stronger resilience. Losing an api-server node has zero impact on the state quorum.
* **Cons**:
  - Double the number of nodes to maintain (e.g., 3 API servers + 3 etcd nodes = 6 nodes total).
  - More complex network policy and certificate management.

---

## 2. Load Balancing the API Server

Since `kube-apiserver` is stateless, it must be fronted by a Load Balancer (LB) to route traffic from worker nodes and admins.

```
                  +--------------------------+
                  | User / kubectl / Workers |
                  +------------+-------------+
                               |
                               v
                  +--------------------------+
                  | External L4 Load Balancer|
                  |   (TCP Pass-Through:6443)|
                  +------------+-------------+
                               |
       +-----------------------+-----------------------+
       |                       |                       |
       v                       v                       v
+---------------+       +---------------+       +---------------+
| Master Node 1 |       | Master Node 2 |       | Master Node 3 |
|  Port 6443    |       |  Port 6443    |       |  Port 6443    |
+---------------+       +---------------+       +---------------+
```

### Production Load Balancer Best Practices:
1. **L4 TCP Load Balancing**: Avoid terminating TLS (L7) at the load balancer level unless strictly necessary. Pass TCP directly to the API servers on port `6443` so clients authenticate directly against the api-server certificate authority.
2. **Health Checks**: Configure the load balancer to perform health checks against the `/livez` or `/readyz` endpoints:
   - **Path**: `https://<apiserver-ip>:6443/livez`
   - **Protocol**: HTTPS (ignore invalid certs if using internal IPs)
   - **Interval**: 5 seconds
   - **Healthy Threshold**: 2, **Unhealthy Threshold**: 3
3. **Split-Brain Load Balancing**: Ensure your load balancer uses round-robin or least-connections routing. Avoid "sticky sessions" to ensure even load distribution.

---

## 3. Multi-Zone Workload Distribution

To survive physical zone failures, workloads must be distributed across failure domains using **Topology Spread Constraints** and **Anti-Affinity**.

### Anti-Affinity vs. Topology Spread:
* **Pod Anti-Affinity**: A binary "do not run together" rule. For example, "never schedule two replicas of `payment-gateway` on the same host." If you have 3 replicas and only 2 nodes, the 3rd replica will remain `Pending`.
* **Topology Spread Constraints**: A flexible scheduling rule governed by `maxSkew`. It allows you to distribute pods proportionally. For example: "distribute pods across zones such that the difference in pod counts is at most 1."

### Cross-Zone Networking and Latency:
When running a multi-zone cluster, nodes in different zones communicate over local regional networks.
* **Latency**: Inter-zone latency is typically 1ms to 2ms, whereas intra-zone latency is sub-millisecond. This slight increase affects etcd's consensus writes (Raft) and database syncs.
* **Egress Cost**: Cloud providers charge for data transferred across availability zones. To minimize these costs, use **Topology-Aware Routing** (or **Topology-Aware Hints** in newer K8s versions) to keep service traffic within the same zone where possible:
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: billing-service
    annotations:
      service.kubernetes.io/topology-mode: Auto
  ```

---

## 4. Disaster Recovery Strategies (Active-Passive vs Active-Active)

For enterprise availability, you may need a strategy that extends beyond a single multi-zone cluster.

| Characteristic | Active-Active (Multi-Cluster) | Active-Passive (Warm Standby) |
|---|---|---|
| **RPO (Data Loss)** | Near 0 (synchronous database replication) | Depends on backup frequency (e.g. 1 hour) |
| **RTO (Recovery Time)** | Seconds (automated DNS failover) | Minutes to Hours (manual restore / DNS switch) |
| **Complexity** | High (requires global load balancers, multi-cluster sync) | Medium (requires clean runbooks and automated scripts) |
| **Cost** | High (running two clusters at full capacity) | Low (passive cluster can be scaled down to zero nodes) |
| **Failover Trigger** | Automatic via Global DNS (e.g., Cloudflare, Route53) | Manual after triage approval |
