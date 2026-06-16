# 🔌 Cross-Cluster Networking: ClusterMesh & Tunnels Under the Hood

To allow workloads running in different clusters to communicate directly, you must configure network routes across VPC and cloud boundaries. This guide explains the technical mechanisms behind flat networks, eBPF routing, and tunnel encapsulation.

---

## 🏗️ 1. Flat Networks vs. Gateway Routing

```
FLAT IP NETWORK (Direct Routing)
[ Pod A: 10.240.1.15 ] ➔ [ Router / VPC Peering ] ➔ [ Pod B: 10.241.2.34 ]
(High performance, zero encapsulation overhead, requires non-overlapping CIDRs)

TUNNELED ROUTING (Submariner / Overlay)
[ Pod A: 10.240.1.15 ]
          │
          ▼
[ Submariner Gateway ] ➔ [ Encapsulated WAN Tunnel (IPsec/WG) ] ➔ [ Submariner Gateway B ]
          │
          ▼
[ Pod B: 10.241.2.34 ]
(Secure encryption over public internet, handles overlapping CIDRs via NAT translation)
```

---

## 🚀 2. Cilium ClusterMesh Under the Hood

Cilium ClusterMesh connects the CNI directory of multiple clusters directly, allowing high-performance eBPF-routed pod-to-pod communication.

### A. Control Plane etcd Synchronization
1.  Every Cilium cluster runs an internal etcd cluster (specifically for Cilium state) or uses the Kubernetes API server to expose endpoint metadata.
2.  In a ClusterMesh setup, the Cilium agent in `Cluster-A` connects directly to the etcd server of `Cluster-B` (and vice-versa).
3.  Cilium synchronizes two main sets of data:
    *   **Identities**: The security identity maps for pods, enabling uniform network policies.
    *   **IP-to-Identity Maps**: Lists of which pod IP addresses have which labels.
4.  Because the identities are shared, you can apply a standard Cilium Network Policy in `Cluster-A` that targets pods in `Cluster-B` using standard labels.

### B. eBPF Packet Redirection
When a packet leaves `Pod-A` (IP `10.240.1.15`) destined for `Pod-B` (IP `10.241.2.34`):
1.  The Cilium eBPF program attached to the pod's virtual ethernet interface (`veth`) intercepts the outbound packet.
2.  It looks up the target IP in its local eBPF map. It discovers the target is in `Cluster-B`.
3.  Instead of routing through the host's standard Linux networking stack (which would drop it or NAT it), the eBPF program redirects the packet directly to the physical interface, either encapsulating it in a VXLAN/Geneve frame or routing it natively if VPC routing tables allow.
4.  Because it operates in eBPF, it bypasses the host iptables completely, reducing latency to near-native hardware speed.

---

## 🛡️ 3. Submariner: Tunneling Overlapping CIDRs

Submariner is a CNCF sandbox project designed to connect clusters with varying network topologies.

### A. The Core Components:
*   **Broker**: A set of CRDs deployed in a central cluster that registers all participating clusters, their endpoint details, and IP ranges.
*   **Gateway Engine**: Deployed as a daemon on designated nodes, it establishes the actual VPN tunnels (using IPsec or WireGuard) to gateways in other clusters.
*   **Route Agent**: Deployed on all worker nodes, it intercepts outbound traffic destined for remote pods and routes it to the local Gateway node.

### B. Globalnet: Overcoming Overlapping CIDRs
If both `Cluster-A` and `Cluster-B` use the pod CIDR `10.244.0.0/16`, routing packets directly is impossible because routers cannot distinguish local from remote targets. Submariner solves this with **Globalnet**:
1.  Globalnet allocates a unique, non-overlapping virtual IP subnet (e.g. `242.0.0.0/8`) to each cluster. This is the **Global IP pool**.
2.  When a service in `Cluster-A` needs to be exposed, Globalnet assigns it a virtual IP from its Global pool (e.g., `242.1.0.5`).
3.  When a pod in `Cluster-B` sends a packet to `242.1.0.5`, the Submariner gateway translates the target IP back to the local Pod IP using **Destination NAT (DNAT)**, and translates the sender's IP to a local global address using **Source NAT (SNAT)**.

---

## 🌐 4. Multi-Cluster Services (MCS) API

To standardize service discovery across multiple clusters, the Kubernetes SIG-Multicluster defined the MCS API:

*   **ServiceExport**: Declared in the host cluster.
    ```yaml
    apiVersion: multicluster.x-k8s.io/v1alpha1
    kind: ServiceExport
    metadata:
      name: inventory-api
      namespace: prod
    ```
*   **ServiceImport**: Automatically generated in importing clusters by the mesh controllers.
*   **DNS Lookup**: The DNS system inside the importing cluster registers the imported service endpoint. Pods can now resolve and access the service using:
    `inventory-api.prod.svc.clusterset.local`
*   **Load Balancing**: The DNS server returns the IP addresses of all endpoints across *both* clusters, or steers traffic based on cluster locality rules (topology-aware routing).
