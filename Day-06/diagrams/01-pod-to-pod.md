# 01 - Pod-to-Pod Communication

Kubernetes enforces a flat network model where every Pod receives a unique, routable IP address within the cluster. Pods can communicate with all other Pods without NAT, regardless of which node they reside on.

## Same Node vs. Cross-Node Packet Flow

```mermaid
graph TD
    %% Styling
    classDef pod fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef netDev fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef node fill:#181825,stroke:#a6e3a1,stroke-dasharray: 5 5,stroke-width:2px,color:#cdd6f4;

    subgraph Node1 [Worker Node 1 - IP: 192.168.1.10]
        PodA[Pod A <br> IP: 10.244.1.5]:::pod -->|eth0| VethA[vethA <br> Virtual Ethernet]:::netDev
        PodB[Pod B <br> IP: 10.244.1.6]:::pod -->|eth0| VethB[vethB <br> Virtual Ethernet]:::netDev
        
        VethA <--> Bridge1[cbr0 / Bridge <br> L2 Switch]:::netDev
        VethB <--> Bridge1
        Bridge1 <--> Eth1[eth0 / Physical NIC]:::netDev
    end

    subgraph Node2 [Worker Node 2 - IP: 192.168.1.11]
        Bridge2[cbr0 / Bridge <br> L2 Switch]:::netDev <--> Eth2[eth0 / Physical NIC]:::netDev
        VethC[vethC <br> Virtual Ethernet]:::netDev <--> Bridge2
        VethC -->|eth0| PodC[Pod C <br> IP: 10.244.2.12]:::pod
    end

    %% Routing
    Eth1 <-->|Physical Network / Overlay Tunnel| Eth2

    %% Text explanations
    class Node1 node;
    class Node2 node;
```

### Explanation of Components
1. **veth (Virtual Ethernet Pair)**: Act as a virtual patch cord. One end is placed inside the Pod's network namespace (exposed as `eth0`), and the other end is bound to the host network bridge (e.g., `vethA`).
2. **cbr0 / Bridge**: An L2 software bridge acting as a local virtual switch. Packets between Pods on the same node (e.g., Pod A to Pod B) are switched locally at L2 by the bridge without ever reaching the physical network interface.
3. **Cross-Node Routing**: When Pod A (10.244.1.5) sends a packet to Pod C (10.244.2.12), the bridge realizes the destination IP is outside its subnet and forwards it to the host routing table. The host routes the packet via its physical NIC (`eth0`) across the network (via BGP routing or VXLAN/Geneve encapsulation) to Node 2.
