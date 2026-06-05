# Production Networking: Lessons Learned at Scale

This document shares architectural design principles and operational guidelines gained from running large-scale Kubernetes networking environments in production.

---

## 1. The MTU Size Mismatch Outage (MTU Math)

One of the most common production networking outages occurs when the Maximum Transmission Unit (MTU) of the virtual container network is set incorrectly.

### The Physics of MTU
The physical ethernet network standard has a default MTU of `1500` bytes. If a container sends a packet of 1500 bytes and the network CNI uses VXLAN overlay encapsulation, the CNI will append an outer header:
* VXLAN overhead = **50 bytes** (IP: 20 bytes + UDP: 8 bytes + VXLAN: 8 bytes + Inner Ethernet: 14 bytes)
* Total outgoing packet size = **1550 bytes**

When this packet reaches a physical network gateway or a cloud routing boundary with an MTU limit of 1500, the packet is silently dropped if the `Don't Fragment` (DF) IP flag is set. This leads to **PMTU Discovery Black Holes**:
* Short UDP/TCP connections (like health checks or small DNS requests) succeed.
* Large TCP streams (like database queries, API payloads, or TLS handshakes) hang and timeout because they exceed the MTU window.

### MTU Reference Chart
Always configure your CNI MTU based on this formula:
$$\text{CNI MTU} \le \text{Host Physical MTU} - \text{Encapsulation Overhead}$$

| CNI Mode | Overlay Overhead | Target CNI MTU (Standard host: 1500) | Target CNI MTU (Jumbo Frame host: 9000) |
|---|---|---|---|
| Direct Routing (BGP) | 0 bytes | 1500 | 9000 |
| IP-in-IP | 20 bytes | 1480 | 8980 |
| VXLAN | 50 bytes | 1450 | 8950 |
| Geneve | 50 bytes | 1450 | 8950 |

---

## 2. Calico IPAM Block Tuning at Scale

By default, Calico allocates IP addresses using a hierarchical scheme. It assigns blocks of IPs (typically `/26` blocks, containing 64 addresses) to individual nodes.

### The Problem: IP Address Waste
If a cluster has 100 nodes and uses a default `/26` block size, Calico allocates $100 \times 64 = 6,400$ IP addresses immediately. 
If you only run 3 pods on each node, you are only utilizing 300 IPs, but 6,100 IP addresses are locked and unavailable for scheduling elsewhere. In an enterprise cloud subnet with limited CIDR space (e.g. `/20` containing 4,096 IPs), your cluster will run out of IPs and refuse to schedule new pods, despite having massive physical host capacity.

### The Solution: Tuning Block Size
For dense nodes running small pods, reduce the block size to `/27` (32 IPs) or `/28` (16 IPs) inside the Calico IPPool configuration:

```yaml
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: default-ipv4-ippool
spec:
  cidr: 10.244.0.0/16
  blockSize: 28 # Allocates blocks of 16 IPs per node
  ipipMode: Always
  natOutgoing: true
```
*Note: Tuning block sizes should only be done during initial cluster provision, as editing block sizes on a live, populated pool requires manual IP migration.*

---

## 3. Data Plane Scaling: eBPF vs. iptables

In large clusters, managing service mapping and policies using `iptables` introduces substantial latency bottlenecks.

```
Rule Evaluation Latency (ms)
  ▲
  │                     /  (iptables - O(N) linear evaluation)
  │                    /
  │                   /
  │                  /
  │─────────────────/──────── (eBPF & IPVS - O(1) hash lookups)
  │
  └──────────────────────────► Number of Services / Policies
```

### Why iptables Fails at Scale
Every packet passing through a node running `kube-proxy` in `iptables` mode must be evaluated against all active firewall rules sequentially. As you deploy more Services and Network Policies, the traversal overhead rises, degrading throughput and increasing latency. Furthermore, updating a single service rule requires `iptables-restore` to rewrite the entire rule set in the kernel, consuming high CPU.

### eBPF Advantages
eBPF (Extended Berkeley Packet Filter) allows Calico to run sandboxed code directly inside kernel hook points. 
* **Hash-Table Lookups:** Maps routes and firewall rules to hash-tables, resulting in $O(1)$ lookups regardless of cluster size.
* **Direct Routing:** Bypasses the host's general TCP/IP stack entirely, routing packets directly from the physical network adapter to the container interface.
* **Source IP Preservation:** Eliminates host SNAT mappings, preserving the original source IP for application logs without requiring complex configurations.

---

## 4. Cross-Zone Cloud Egress Cost Optimization

Cloud providers (like AWS, GCP, Azure) do not charge for network traffic inside the same Availability Zone (AZ). However, they charge heavily for traffic crossing AZ boundaries (often \$0.01 per GB in both directions).

### The "Default" Latency and Cost Trap
A frontend pod in Zone A making database queries to a replica pod in Zone B triggers cross-AZ egress charges. In high-throughput microservices, this can result in thousands of dollars in monthly cloud billing.

### Mitigation Strategies
1. **Topology-Aware Routing:** Enable `topologyKeys` or `topology.kubernetes.io/zone` routing on Kubernetes Services, forcing the scheduler to route connections to local endpoints in the same zone when available.
2. **Affinity Policies:** Use Pod Anti-Affinity rules to distribute processing replicas evenly, but use Pod Co-location Affinity to keep tightly coupled backend-to-database processing streams inside the same availability zone.
