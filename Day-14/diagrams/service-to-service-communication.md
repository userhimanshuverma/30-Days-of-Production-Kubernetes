# Service-to-Service Communication

This diagram illustrates how virtual Service IP addresses (ClusterIPs) are translated into actual Pod target IPs using Netfilter DNAT rules configured by kube-proxy.

```mermaid
graph TD
    PodA[Pod A - 10.244.1.5]
    ServiceIP[ClusterIP Service: backend-svc<br/>IP: 10.96.0.100:80]
    
    subgraph KernelNAT [Node 1 Linux Kernel - kube-proxy iptables/IPVS]
        NATRule{Select target Endpoint<br/>via DNAT & Weighting}
        Endpoint1[Pod B1 Target - 10.244.1.12:8080]
        Endpoint2[Pod B2 Target - 10.244.2.10:8080]
    end

    PodA ==> |Sends request to 10.96.0.100| ServiceIP
    ServiceIP ==> NATRule
    
    NATRule ==> |50% chance DNAT| Endpoint1
    NATRule ==> |50% chance DNAT| Endpoint2
    
    Endpoint1 ==> |Direct route| PodB1[Pod B1 - Same Node]
    Endpoint2 ==> |Overlay route| PodB2[Pod B2 - Remote Node]
```

### Destination NAT (DNAT) Mechanics:
1. **Virtual VIP:** A Service IP (ClusterIP) does not correspond to a physical network adapter. It exists only as a configuration entry in host NAT tables.
2. **Kube-Proxy Sync Loop:** Kube-proxy monitors the Kubernetes API for Services and Endpoints. It constantly updates the node's `iptables` or `IPVS` rules to map Service IPs to active Pod IPs.
3. **Randomized Load Balancing:** When a packet targeted at `10.96.0.100` leaves Pod A, the host kernel intercepts it and applies DNAT (Destination Network Address Translation), replacing the destination Service IP with a randomly chosen backend Pod IP (e.g. `10.244.2.10`) before routing.
