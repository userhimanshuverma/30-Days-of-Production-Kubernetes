# 📖 Day 6 Notes: Deep Dive into Kubernetes Services & Networking

## Introduction: Why Kubernetes Networking Exists

In traditional infrastructure, servers are static. They have fixed IP addresses, and you write those IPs into configuration files. In a distributed, containerized system like Kubernetes, this model falls apart:
1. **Dynamic Scaling**: Pods are scaled up and down dynamically.
2. **Ephemerality**: Pods are transient. If a Pod crashes, it is terminated, and a new one is scheduled with a **different IP address**.
3. **No Direct IPs**: You can never hardcode Pod IP addresses in your application code.

To solve this, Kubernetes introduces the **Service** abstraction—a stable, logical access point with a permanent IP (ClusterIP) and a permanent DNS name that load balances traffic across an active set of dynamic Pods.

---

## 1. The Ephemeral Pod Problem & Stable Abstractions

Think of a Pod like a **temp employee** working in a mail room. They are given a temporary desk phone (the Pod IP). If they quit (the Pod crashes), a new employee is hired, assigned to a new desk, and gets a new desk phone (a new Pod IP).

If external clients had to call these individual desks directly, they would spend all their time updating their contact books.

A **Kubernetes Service** acts as a **central operator (or hotline)**. The service has a single phone number (the ClusterIP) that never changes. When a client dials the hotline, the operator automatically routes the call to whichever temp employees are currently active and available.

---

## 2. ClusterIP: Internal-Only Virtual Routing

The `ClusterIP` is the default service type. It allocates a Virtual IP (VIP) from a dedicated subnet (the `service-cluster-ip-range` configured on the API server, e.g., `10.96.0.0/12`).

### The Illusion of the ClusterIP
A common point of confusion is: **Where does the ClusterIP interface live?**
* If you run `ifconfig` or `ip addr show` inside a Pod or on a worker node, **you will not find the ClusterIP listed on any interface**.
* It is a **virtual IP** (a "ghost" IP). It does not exist in any hardware or virtual interface.
* Instead, it exists only as **routing entries** inside the Linux kernel's Netfilter/iptables or IPVS lookup tables.

When a Pod sends a packet to `10.96.14.22` (the ClusterIP), the host node's kernel intercepts it *before* it leaves the node, performs destination NAT (DNAT) to change the destination to a real Pod IP (e.g., `10.244.2.12`), and forwards the packet onto the network.

---

## 3. NodePort: Exposing Services to the Host Network

A `NodePort` Service exposes the application on a dedicated port (default `30000-32767`) on the physical IP of **every worker node** in the cluster.

### The Double-NAT Path (Default: `externalTrafficPolicy: Cluster`)
When an external client calls `Node-1-IP:30080`:
1. **First NAT (DNAT)**: The node intercepts the packet on port 30080. It performs DNAT, rewriting the destination to a target Pod IP.
2. **Second NAT (SNAT)**: If the selected Pod is on **Node 2**, Node 1 performs Source NAT (SNAT), replacing the client's IP with Node 1's own internal IP.
3. **The Hop**: The packet travels from Node 1 to Node 2.
4. **The Return**: Pod replies to Node 1, which un-NATs and returns it to the client.

### Optimizing with `externalTrafficPolicy: Local`
By setting `externalTrafficPolicy: Local`, you configure the node to **only** route traffic to Pods running on that exact node.
* **Pros**: 
  * Eliminates the cross-node network hop (saving latency).
  * Preserves the client's original IP (crucial for security logging, rate limiting, and GeoIP detection).
* **Cons**:
  * Health checking: The cloud load balancer must health-check the special NodePort endpoint (default port 10256) to ensure it only sends traffic to nodes hosting at least one replica.
  * Load Imbalance: Traffic is distributed equally to nodes, not pods. If Node A has 1 pod and Node B has 9 pods, the pod on Node A handles 9x more traffic than the pods on Node B.

---

## 4. LoadBalancer: Directing Cloud Provider Load Balancers

The `LoadBalancer` Service type acts as a controller wrapper. 
1. When created on a cloud-managed Kubernetes service (EKS, GKE, AKS), the **Cloud Controller Manager (CCM)** detects the service creation.
2. The CCM talks to the cloud provider's API (e.g., AWS EC2 API) to provision an external Load Balancer (e.g., AWS NLB).
3. The cloud load balancer is configured to route traffic to the cluster nodes on the Service's `NodePort`.
4. The traffic follows the NodePort path down to the Pods.

---

## 5. DNS and CoreDNS Internals

DNS-based service discovery is powered by **CoreDNS**.
* CoreDNS runs as a deployment (usually 2 replicas) and is exposed via a ClusterIP named `kube-dns` in the `kube-system` namespace.
* Kubelet automatically configures every container's `/etc/resolv.conf` to use this `kube-dns` ClusterIP as its primary resolver.

### How DNS Suffixes Work
When your code makes a query like `curl http://web-backend-service/`:
1. The OS resolver reads `/etc/resolv.conf`.
2. It looks at the `search` domains: `default.svc.cluster.local`, `svc.cluster.local`, `cluster.local`.
3. It appends these domains in order, querying CoreDNS:
   * `web-backend-service.default.svc.cluster.local` (Success! CoreDNS returns the ClusterIP).

### Cross-Namespace Resolution
To talk to a service in a different namespace (e.g., the `database` namespace):
* You query: `database-service.database.svc.cluster.local`.

---

## 6. kube-proxy modes: iptables vs. IPVS

`kube-proxy` is the daemon responsible for keeping the L4 routing rules updated on every node. It supports two primary backend modes:

### A. iptables Mode (Default)
* **Mechanism**: Uses Netfilter rules chains.
* **How it works**: For every Service and Endpoint, it adds rules. For a service with 3 backends, it adds 1 rule matching the service IP, and 3 rule targets using the `statistic` module to randomly select one of the three backend pods.
* **Limitations**: 
  * Sequential evaluation: When a packet arrives, the kernel evaluates iptables rules sequentially ($O(N)$). If you have 10,000 rules, processing every packet consumes substantial CPU.
  * Rule sync latency: Any change to any service requires rewriting the entire iptables rule set in kernel space, causing a locking delay in large clusters.

### B. IPVS Mode
* **Mechanism**: Uses the Linux IP Virtual Server kernel module, specifically built for Layer-4 load balancing.
* **How it works**: IPVS stores rules in memory hash tables ($O(1)$ lookup complexity). 
* **Benefits**: 
  * Scale-independent performance: A cluster with 10,000 services has the exact same routing latency as a cluster with 5 services.
  * Real load-balancing algorithms: Supports actual algorithms like Least Connections (route to the pod handling the fewest connections), Round-Robin, or Source Hashing.
