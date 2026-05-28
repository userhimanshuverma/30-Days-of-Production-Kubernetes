# 11 - Cross-Node Networking: Overlay vs. Direct Routing

When Pod A on Node 1 wants to communicate with Pod C on Node 2, the packets must be transmitted across the underlying physical network. Kubernetes CNIs (Container Network Interfaces) accomplish this using one of two primary strategies: **Overlay Networks** or **Direct Routing**.

## Architectural Comparison

```mermaid
graph TD
    %% Styling
    classDef pod fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef encap fill:#f9e2af,stroke:#f89820,stroke-width:2px,color:#cdd6f4;
    classDef phy fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;

    subgraph Overlay [Overlay Network (e.g., Flannel / Calico VXLAN)]
        PodA_O[Pod A <br> 10.244.1.5]:::pod -->|Packet: Pod A -> Pod C| VXLAN_Encap[VXLAN Interface <br> Encapsulates Pod IP Packet <br> inside Host UDP Packet]:::encap
        VXLAN_Encap -->|Host Packet: Node 1 IP -> Node 2 IP| PhysNet_O[Physical Network Fabric]:::phy
        PhysNet_O --> VXLAN_Decap[VXLAN Interface Node 2 <br> Strips Host UDP header]:::encap
        VXLAN_Decap -->|Delivers original packet| PodC_O[Pod C <br> 10.244.2.12]:::pod
    end

    subgraph Direct [Direct Routing (e.g., Calico BGP / AWS VPC CNI)]
        PodA_D[Pod A <br> 10.244.1.5]:::pod -->|Packet: Pod A -> Pod C| HostRoute[Host Routing Table <br> No Encapsulation]
        HostRoute -->|Packet sent as-is| PhysNet_D[Physical Router <br> Learns Pod subnets via BGP]:::phy
        PhysNet_D -->|Delivers packet directly| PodC_D[Pod C <br> 10.244.2.12]:::pod
    end
```

### Technical Trade-Offs

#### 1. Overlay Networks (VXLAN / Geneve)
* **How it works**: Wraps the Pod packet inside a standard UDP header (typically port 4789). To the physical network routers, it looks like standard node-to-node UDP traffic.
* **Pros**: Works on any infrastructure (AWS, GCP, VMware, bare metal) without configuration changes to physical network switches.
* **Cons**: 
  * **MTU Overhead**: Encapsulation adds a 50-byte header, reducing the Max Transmission Unit (MTU) from 1500 to 1450. If MTU is misconfigured, packets are fragmented, causing performance issues.
  * **CPU Penalty**: Nodes must encrypt/decrypt (or encapsulate/decapsulate) every packet in software.

#### 2. Direct Routing (BGP / Cloud VPC Native)
* **How it works**: Worker nodes act as routers and announce their Pod subnets directly to the VPC router (e.g., AWS VPC CNI maps AWS ENI secondary IPs directly to Pods, so Pod IPs are real VPC IPs).
* **Pros**: 
  * **Maximum Performance**: No encapsulation overhead, running at wire speed.
  * **Standard MTU**: Standard 1500-byte MTU (or 9000 jumbo frames).
  * **Native Visibility**: Network firewalls and VPC flow logs can see actual Pod IPs directly.
* **Cons**: Requires tight integration with the underlying network topology and API permissions (e.g., IAM roles for AWS VPC CNI, BGP peering configurations for on-premise routers).
