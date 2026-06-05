# 🌐 Day 14: Kubernetes Networking Internals
### 🏷️ PHASE 2 — RUNNING REAL APPLICATIONS

Welcome to Day 14. Today, we peel back the abstraction layers of Kubernetes to examine its most critical infrastructure subsystem: **Networking**. 

In traditional virtual machine deployments, networks are static, ports are hardcoded, and security boundaries are enforced by perimeter firewalls. In Kubernetes, applications are dynamic, Pods are ephemeral, and IP addresses are constantly created and destroyed. 

To run reliable, secure, and performant workloads in production, platform engineers must understand the underlying mechanics of how packets flow through the cluster. Today, we will deep dive into CNI plugins, overlay networking, Calico, Network Policies, and trace the step-by-step lifecycle of a network packet.

---

## 🗺️ Day 14 Directory Structure

Here is how today's learning resources are organized:
- [notes/networking-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-14/notes/networking-deep-dive.md) — Comprehensive technical reference detailing network namespaces, virtual ethernet (`veth`) plumbing, VXLAN encapsulation, BGP routing, and iptables rules.
- [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-14/diagrams/) — 12 detailed network architecture and packet flow diagrams.
- [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-14/manifests/) — Production-ready YAML manifests for microservice pods and security policies.
- [labs/](file:///d:/30_Days_of_Production_Kubernetes/Day-14/labs/) — Step-by-step hands-on engineering labs.
  - [Lab 1: CNI and Calico Network Plumbing](file:///d:/30_Days_of_Production_Kubernetes/Day-14/labs/lab-1-cni-and-calico.md)
  - [Lab 2: Implementing Zero-Trust Network Policies](file:///d:/30_Days_of_Production_Kubernetes/Day-14/labs/lab-2-network-policies.md)
- [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-14/production-notes/lessons-learned.md) — SRE insights on overlay network latency, MTU sizing calculations, eBPF data planes, and BGP scaling.
- [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-14/troubleshooting/playbook.md) — Resolution playbooks for 10 common real-world networking failures.
- [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-14/exercises/challenges.md) — Challenge scenarios to test your CNI IPAM limits and network policy implementation.
- [resources/kubernetes-packet-explorer.html](file:///d:/30_Days_of_Production_Kubernetes/Day-14/resources/kubernetes-packet-explorer.html) — Futuristic, interactive, single-page HTML packet flow simulator.

---

## 1. Why Kubernetes Networking Is Different

In classical virtualization, multiple VMs share a host, and ports are mapped via Network Address Translation (NAT) or virtual port groups:

```
[ VM 1: Port 80 ] ──(NAT)──> [ Host: Port 8081 ] ──┐
                                                    ├──> [ Router ]
[ VM 2: Port 80 ] ──(NAT)──> [ Host: Port 8082 ] ──┘
```

Kubernetes discards this complexity by mandating a **flat networking model** based on three fundamental requirements:
1. Every Pod gets its own unique IP address (no NAT required for Pod-to-Pod communication).
2. Pods on a node can communicate with all Pods on all nodes without NAT.
3. The IP that a Pod sees as its own is the same IP that other Pods see it as.

This creates an environment where containers can be treated like physical hosts on a LAN.

### The Pod-to-Pod Model
Because every Pod has a unique IP, applications can bind to standard ports (like HTTP `80` or database `5432`) without port conflicts. Containers inside the same Pod share the same network namespace and can communicate via `localhost`.

### Node Boundaries
To cross the physical boundary between host nodes, the cluster utilizes either **overlay networks** (encapsulating packets inside host packets) or **underlay routing** (exposing Pod IPs directly to the physical network via BGP).

---

## 2. CNI (Container Network Interface) Deep Dive

Kubernetes does not contain a built-in container networking engine. Instead, it delegates IP address allocation and packet routing to external plugins via the **Container Network Interface (CNI)** specification.

```
                  ┌──────────────┐
                  │   Kubelet    │
                  └──────┬───────┘
                         │ (JSON Config via stdin)
                         ▼
             ┌───────────────────────┐
             │ CNI Plugin Executable │
             │   (e.g., Calico)      │
             └──────────┬────────────┘
       ┌────────────────┴────────────────┐
       ▼                                 ▼
[ Create Network Namespace ]   [ Allocate IP & Wire Interfaces ]
```

### What is CNI?
CNI is a CNCF specification defining a minimal JSON interface between container runtimes (like `containerd`) and networking plugins. The runtime invokes the CNI plugin executable with environment variables indicating the operation (`ADD`, `DEL`, `CHECK`, `VERSION`) and parameters specifying the target container's namespace.

### The Plumbing Process
When Kubelet schedules a Pod:
1. Kubelet creates a new Linux network namespace (`netns`) for the container.
2. Kubelet calls the CNI plugin with the `ADD` command.
3. The CNI plugin allocates an IP address from its **IP Address Management (IPAM)** pool.
4. The CNI plugin creates a Virtual Ethernet (`veth`) pair.
5. One end of the `veth` is placed inside the Pod namespace (named `eth0`), and the other end remains in the host's root namespace (often named `caliXXXX` or `vethXXXX`).
6. The CNI plugin configures host routing tables, ARP entries, or virtual bridges to ensure packets are routed to this interface.

---

## 3. Overlay Networking Fundamentals

When Pod A on Node 1 wants to talk to Pod B on Node 2, the physical network fabric (which only knows about host Node IPs) needs to know what to do with the Pod IP packets. **Overlay Networking** solves this via encapsulation.

```
+-------------------------------------------------------------------------+
|                  Original IP Packet (Pod A -> Pod B)                    |
|                [ Src: 10.244.1.5 ] ---> [ Dst: 10.244.2.10 ]            |
+-------------------------------------------------------------------------+
                                    │
                                    ▼ (Encapsulated by Node 1 Kernel)
+-------------------------------------------------------------------------+
|  Outer IP Header  |  VXLAN/UDP  |  Inner IP Header  |  Original Packet  |
| Src: Node 1 IP    | Port: 4789  | Src: Pod A IP     |  Payload          |
| Dst: Node 2 IP    |             | Dst: Pod B IP     |                   |
+-------------------------------------------------------------------------+
```

### Virtual Networks & Encapsulation
An overlay network is a logical network built on top of an existing physical network. 
* **Encapsulation:** Before leaving Node 1, the original packet is wrapped inside an outer packet (adding a VXLAN or IP-in-IP header). The source IP becomes Node 1's physical IP, and the destination becomes Node 2's physical IP.
* **Decapsulation:** When the packet reaches Node 2, the kernel strips away the outer headers and forwards the original inner packet directly into Pod B's `veth` interface.

### Overlay Protocols
* **VXLAN (Virtual Extensible LAN):** Encapsulates Layer 2 Ethernet frames inside Layer 4 UDP packets (port `4789`). Highly standard, works across cloud providers, but has a 50-byte header overhead.
* **IP-in-IP:** Encapsulates Layer 3 IP packets directly inside IP packets (IP protocol number `4`). Simpler, slightly less overhead (20 bytes), but some cloud environments block IP-in-IP traffic.

---

## 4. Calico Architecture

**Calico** is a highly popular enterprise-grade CNI plugin. While it supports overlay networking (VXLAN and IP-in-IP), it is famous for its **no-encapsulation mode**, routing Pod traffic directly via Border Gateway Protocol (BGP).

```
         ┌──────────────────────────────────────────────────┐
         │                  Kubernetes API                  │
         └────────────────────────┬─────────────────────────┘
                                  │ (Sync configuration)
                                  ▼
      ┌────────────────────────────────────────────────────────┐
      │                      Calico Felix                      │
      │   (Runs on each Node, programs IP Routes & iptables)   │
      └──────┬──────────────────────────────────────────┬──────┘
             │                                          │
             ▼                                          ▼
     ┌───────────────┐                          ┌───────────────┐
     │ BIRD / BGP    │                          │ Confd         │
     │ (Peers routes)│                          │ (Renders BGP) │
     └───────────────┘                          └───────────────┘
```

### Key Components
1. **Felix:** A daemon running on every node. It reads the Kubernetes API state and programs host routes, network interfaces, and Linux kernel firewall configurations (iptables, IPVS, or eBPF).
2. **BIRD:** A dynamic routing daemon. It propagates Pod routing information from the local host to other nodes in the cluster using BGP.
3. **confd:** A configuration engine that monitors Calico's data store and updates BIRD configuration files on the fly.
4. **Typha:** A fan-out proxy that prevents Calico Felix agents from overwhelming the Kubernetes API server in clusters larger than 100 nodes.

### Direct Routing (BGP)
In Calico's BGP mode, nodes act as software routers. Node 1 advertises its local Pod IP CIDR (e.g., `10.244.1.0/24`) to Node 2. When Node 2 wants to send a packet to `10.244.1.5`, it checks its local routing table, sees that `10.244.1.0/24` is reachable via Node 1's physical IP, and forwards the packet directly *without overlay encapsulation*.

---

## 5. Network Policies

By default, Kubernetes networking is **non-isolated**. Any Pod can talk to any other Pod in the cluster. **Network Policies** allow you to restrict this traffic flow declaratively.

```
       [ Unsecured Frontend ] ────┐
                                  ├─(BLOCKED!)──> [ Database Pod ]
       [ Secure Backend Pod ] ────┘ (ALLOWED)
```

### Traffic Rules
* **Default Allow:** The starting state. If no policies apply to a Pod, all incoming and outgoing connections are accepted.
* **Default Deny:** A security best practice. Once a Network Policy selects a Pod (using a `podSelector`), all traffic to/from that Pod is blocked unless explicitly permitted by a rule.
* **Ingress Rules:** Rules filtering incoming traffic based on source namespaces (`namespaceSelector`), source pods (`podSelector`), or CIDR IP ranges.
* **Egress Rules:** Rules filtering outgoing traffic based on destination namespaces, destination pods, ports, or external IP blocks.

Network Policies are **layer 3/4 controls** (IPs and Ports). They are enforced directly at the node's virtual interfaces by the CNI (e.g., Calico Felix creating iptables rules or eBPF programs).

---

## 6. Detailed Packet Journey (Flow Map)

Here is exactly how a request travels from a user, through a pod, across nodes, and down to a destination pod:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                               USER REQUEST                                │
│                              (curl backend)                               │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                              CONTAINER LEVEL                              │
│ 1. Pod A Namespace: Resolves 'backend' DNS via CoreDNS.                   │
│ 2. Routes packet via 'eth0' (interface inside Pod namespace).             │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                                HOST LEVEL                                 │
│ 3. Virtual Interface (veth): Packet crosses bridge to host namespace.     │
│ 4. Host Routing Table: Destination is Pod B (10.244.2.10).                │
│    Route table indicates Pod B is reachable via Node 2 IP (192.168.1.20). │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                             ENCAPSULATION (Overlay)                       │
│ 5. VXLAN Device: Kernel wraps packet in UDP frame (Port 4789).            │
│ 6. Outward Nic: Packet departs Node 1 physical interface.                 │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                              [ Physical Fabric ]
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                            DECAPSULATION (Overlay)                        │
│ 7. Inward Nic: Packet arrives on Node 2 physical interface.               │
│ 8. VXLAN Device: Kernel detects UDP Port 4789, strips outer UDP/VXLAN.    │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                            DESTINATION DELIVERY                           │
│ 9. Policy Check: Calico Felix checks iptables/eBPF rules (Permits traffic)│
│ 10. Virtual Interface: Packet flows through target veth (caliXXXX).       │
│ 11. Pod B Namespace: Packet enters target namespace interface 'eth0'.     │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Production Examples & Scenarios

### Microservices Communication
A common production pattern limits frontend apps to only communicate with middleware APIs, blocking direct access to other sensitive internal tools.

### Database Isolation
Zero-trust databases must block all ingress traffic by default, only whitelisting incoming TCP connections on port `5432` from designated backend application Pods.

### Multi-Tenant Clusters
In multi-tenant setups, different namespaces host different customers. Network Policies enforce strict boundaries:
* Namespace `tenant-a` Pods cannot access Namespace `tenant-b` Pods.
* Infrastructure services (like Prometheus or CoreDNS) are selectively whitelisted.

---

## 🏁 Summary of Daily Tasks

To complete Day 14, proceed with the following steps:
1. **Explore Architecture Diagrams:** Study the [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-14/diagrams/) to visualize CNI workflows, overlay encapsulation, and BGP routing.
2. **Read Deep-Dive Notes:** Review [notes/networking-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-14/notes/networking-deep-dive.md) to understand kernel-level network plumbing.
3. **Interactive Simulation:** Open the [Kubernetes Packet Explorer Simulator](file:///d:/30_Days_of_Production_Kubernetes/Day-14/resources/kubernetes-packet-explorer.html) in your browser to experience packet lifecycle routing.
4. **Execute Hands-on Labs:**
   * Run [Lab 1: CNI and Calico Network Plumbing](file:///d:/30_Days_of_Production_Kubernetes/Day-14/labs/lab-1-cni-and-calico.md) to inspect interface bindings.
   * Run [Lab 2: Implementing Zero-Trust Network Policies](file:///d:/30_Days_of_Production_Kubernetes/Day-14/labs/lab-2-network-policies.md) to implement default deny policies.
5. **Study Production Best Practices:** Read [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-14/production-notes/lessons-learned.md) to learn about MTU problems, latency overhead, and scaling limits.
6. **Review Troubleshooting Playbook:** Walk through [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-14/troubleshooting/playbook.md) to practice resolving routing and policy failures.
7. **Complete Challenges:** Solve the CNI and Network Policy scenarios in [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-14/exercises/challenges.md).
