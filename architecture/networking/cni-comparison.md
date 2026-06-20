# Kubernetes CNI comparison: Flannel, Calico, and Cilium

This reference sheet analyzes the design characteristics and performance trade-offs of the most common Container Network Interface (CNI) plugins.

---

## 📊 Technical Comparison Matrix

| Feature | Flannel | Calico | Cilium |
| :--- | :--- | :--- | :--- |
| **Primary Data Path** | Overlay (VxLAN, host-gw) | Underlay (BGP) / Overlay (VxLAN, IP-in-IP) | eBPF (direct routing or VxLAN/Geneve overlay) |
| **Network Policies** | No (Requires Canal helper) | Yes (L3/L4 Policies) | Yes (L3/L4/L7 Application Layer Policies) |
| **Performance Overhead** | Moderate (VxLAN encapsulation) | Minimal (Near native wire speed via BGP) | Ultra-Low (Bypass Linux iptables stack) |
| **kube-proxy Replacement** | No | No (Uses iptables/IPVS) | Yes (Full eBPF-based service routing) |
| **Encryption Support** | IPsec | WireGuard / IPsec | WireGuard / IPsec |
| **Scalability** | Low-Medium | Extremely High (Used in huge clusters) | Extremely High |
| **Use Case** | Dev / Test clusters | Standard enterprise environments | Modern cloud-native platform setups |

---

## 🔍 CNI Architecture Highlights

### 1. Flannel (Simplified Bridging)
Flannel is a basic, lightweight overlay network. It creates a flat network subnet configuration across the cluster, allocating a local subnet range to each node host.
*   **How it works**: It wraps raw IP packets inside a UDP VxLAN frame, sending them to target host machines where they are unwrapped and bridged to local pod runtimes.

### 2. Calico (BGP Routing & Policy)
Calico is an SRE favorite for large scaling networks.
*   **How it works**: Instead of wrapping packets, Calico routes packets natively. It uses a virtual router daemon (`Felix`) on each node and exchanges route tables between hosts using the Border Gateway Protocol (BGP). This approach removes overlay wrapping overhead, enabling wire-speed networking.

### 3. Cilium (eBPF-Driven Security)
Cilium bypasses the traditional Linux kernel routing table and IP tables rules.
*   **How it works**: Cilium dynamically compiles and attaches **eBPF (Extended Berkeley Packet Filter)** bytecode programs directly to socket descriptors in the Linux kernel. When a pod makes an API request to another service, Cilium intercepts it at the socket interface level, avoiding context switching overhead. This enables L7 HTTP path routing and identity-based security policies.
