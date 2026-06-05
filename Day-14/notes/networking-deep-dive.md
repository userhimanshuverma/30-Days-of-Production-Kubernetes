# Kubernetes Networking Internals: A Deep Dive Reference Guide

This document provides a highly technical, kernel-level reference guide to Kubernetes Networking subsystems, focusing on network namespaces, the Container Network Interface (CNI) specification, overlay networking encapsulation, Calico's control plane, and Kube-proxy load balancing modes.

---

## 1. The Container Network Interface (CNI) Specification

The Container Network Interface (CNI) is a standard proposed by CoreOS and maintained by the CNCF. Its core objective is to define a clean interface between container runtimes (such as `containerd` or `CRI-O`) and network configuration plugins.

### Network Namespaces (`netns`)
In Linux, network isolation is achieved via **network namespaces**. Each namespace contains its own loopback device, network interfaces, IP routing tables, and firewall rules (`iptables` / `nftables`). 

When Kubelet instructs the container runtime to launch a Pod, the runtime creates a network namespace before starting any container processes. This namespace path (e.g. `/var/run/netns/cni-7c2a41d0-b30c-2e91-c918-09a8f2762a4d`) is passed directly to the CNI plugin.

### CNI Operations
The CNI specification dictates that the runtime communicates with the plugin using environment variables and JSON configurations sent via standard input (`stdin`). The key operations are:

* **`ADD`:** Attach a container to a network. Creates virtual adapters, assigns IP addresses, configures host routes, and updates ARP tables.
* **`DEL`:** Detach a container from a network. Frees IP addresses back to the IPAM allocator and deletes host virtual interfaces.
* **`CHECK`:** Query the CNI plugin to ensure the container network is configured correctly and has not lost link connectivity.
* **`VERSION`:** Query the supported CNI specification versions.

### CNI Configuration File Anatomy
CNI configuration files are stored at `/etc/cni/net.d/`. They are evaluated in alphabetical order. Below is a detailed inspection of a standard Calico configurations list file (`10-calico.conflist`):

```json
{
  "name": "k8s-pod-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "calico",
      "log_level": "info",
      "datastore_type": "kubernetes",
      "nodename": "worker-node-1",
      "ipam": {
        "type": "calico-ipam",
        "assign_ipv4": "true",
        "assign_ipv6": "false"
      },
      "policy": {
        "type": "k8s"
      },
      "securityContext": {
        "privileged": true
      }
    },
    {
      "type": "portmap",
      "capabilities": {"portMappings": true},
      "snat": true
    }
  ]
}
```

---

## 2. Overlay vs. Underlay Networking

How do containers communicate across separate nodes? Kubernetes supports two primary models:

### A. Overlay Networking (Encapsulation)
An overlay network creates a virtual logical network on top of the physical network. The physical network infrastructure remains completely unaware of Pod IP addresses.

#### 1. VXLAN (Virtual Extensible LAN)
* **How it works:** Envelopes Layer 2 Ethernet frames inside Layer 4 UDP packets (default port `4789`).
* **MTU Impact:** Adds a 50-byte header overhead. If the physical MTU is `1500` bytes, the CNI MTU must be set to `1450` bytes to prevent fragmentation.
* **Compatibility:** Highly compatible. Works across virtualized platforms (AWS, Azure, GCP) and physical datacenters because it runs as standard UDP traffic.

#### 2. IP-in-IP (IP encapsulation)
* **How it works:** Wraps Layer 3 IP packets directly inside Layer 3 IP packets (using IP Protocol number `4`).
* **MTU Impact:** Adds a 20-byte header overhead (reducing the CNI MTU to `1480` bytes on a standard `1500` byte link).
* **Compatibility:** Lower compatibility than VXLAN. Some cloud firewalls and network devices block IP protocol 4 packets, requiring overlay fallback or VXLAN setups.

---

### B. Underlay/Direct Routing (No Encapsulation)
Direct routing exposes Pod IP ranges directly to the network fabric. Nodes act as software routers, and Pod IPs are treated as routable subnet addresses.

```
                  ┌──────────────────────┐
                  │ Core Physical Router │
                  └──────────┬───────────┘
            ┌────────────────┴────────────────┐
            ▼ (Direct route advertised)       ▼ (Direct route advertised)
    ┌───────────────┐                 ┌───────────────┐
    │ Worker Node 1 │                 │ Worker Node 2 │
    │ Pod IP Range: │                 │ Pod IP Range: │
    │ 10.244.1.0/24 │                 │ 10.244.2.0/24 │
    └───────────────┘                 └───────────────┘
```
* **BGP (Border Gateway Protocol):** Dynamic routing protocol used to advertise Pod subnet locations. When a node boots, its routing daemon tells local network switches: "To reach my Pod CIDR `10.244.1.0/24`, send packets directly to my physical IP `192.168.1.10`."
* **Pros:** Peak performance. Zero encapsulation CPU overhead and zero packet size reduction.
* **Cons:** Hard to configure on public clouds (GCP/AWS block un-assigned IPs on host network adapters). Best suited for bare-metal and on-premises datacenters.

---

## 3. Calico Routing Modes & Datapath

Calico Felix installs dynamic routes directly into the Linux kernel routing table. Let's inspect a host node's routing table running Calico:

```bash
ip route
```

**Output Breakdown:**
```
default via 192.168.1.1 dev eth0 proto dhcp src 192.168.1.10 metric 100 
10.244.1.0/24 dev vxlan.calico proto bird
10.244.2.5 dev cali83f9eba8ac0 scope link
```

### Routing Entries Decoded:
1. `10.244.1.0/24 dev vxlan.calico proto bird`: Tells the kernel that to reach Pods on Node 2 (which hosts IP subnet `10.244.1.0/24`), packets must be routed through the virtual `vxlan.calico` device. This entry was written by the BIRD BGP daemon.
2. `10.244.2.5 dev cali83f9eba8ac0 scope link`: Tells the kernel that Pod IP `10.244.2.5` resides locally on the node and is directly wired to local interface `cali83f9eba8ac0`. This entry was written by Felix.

---

## 4. Kube-Proxy Implementation Modes

`kube-proxy` is responsible for implementing the **Service** abstraction, translating Virtual IPs (VIPs) to target Pod IPs. It operates in three main modes:

### 1. User Space Mode (Deprecated)
* **Mechanics:** kube-proxy opens an actual port on the host. Netfilter rules redirect Service VIP traffic to this port. kube-proxy then proxies the connection to a backend pod.
* **Performance:** Extremely slow. Requires copying packets back and forth between kernel-space and user-space for every packet.

### 2. iptables Mode
* **Mechanics:** kube-proxy writes large sequential lists of Netfilter `iptables` rules. When a packet targets a Service VIP, Netfilter intercepts it and DNATs it to a random Pod IP.
* **Scaling Limit:** Rules are evaluated sequentially ($O(N)$ lookup complexity). In a cluster with 10,000 Services, the kernel must traverse thousands of rules per packet, causing latency spikes and high CPU utilization.

### 3. IPVS (IP Virtual Server) Mode
* **Mechanics:** kube-proxy utilizes IPVS, a Linux L4 load-balancer built into the kernel. It uses hash tables to map VIPs to backends.
* **Scaling Limit:** Hash table lookups are instant ($O(1)$ complexity). Performance remains flat even with 100,000 services, making it the standard choice for enterprise scale.

### 4. eBPF Mode (CNI Direct - e.g., Calico eBPF / Cilium)
* **Mechanics:** Bypasses `kube-proxy` entirely. Custom eBPF programs are compiled and loaded directly into the network driver queue (e.g. XDP or TC hook).
* **Performance:** Fastest possible path. The packet is load-balanced and translated at the network card driver level, before the packet payload is even copied into the host's general network memory stack.
