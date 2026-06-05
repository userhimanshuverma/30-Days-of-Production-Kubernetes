# Production Network Topology (BGP Peering)

This diagram visualizes a scalable production network topology utilizing BGP Route Reflectors and Top-of-Rack (ToR) hardware routers, avoiding the O(N²) scaling overhead of a full-mesh BGP network.

```mermaid
graph TB
    subgraph CoreFabric [Datacenter Network Core]
        CoreRouter1[Core Router A]
        CoreRouter2[Core Router B]
    end

    subgraph Rack1 [Server Rack 1]
        ToR1[Top-of-Rack Switch / BGP Peer]
        
        Node1_1[Worker Node 1 - RR]
        Node1_2[Worker Node 2]
        Node1_3[Worker Node 3]
        
        Node1_2 <--> |Internal Peering| Node1_1
        Node1_3 <--> |Internal Peering| Node1_1
        Node1_1 <--> |BGP Uplink| ToR1
    end

    subgraph Rack2 [Server Rack 2]
        ToR2[Top-of-Rack Switch / BGP Peer]
        
        Node2_1[Worker Node 4 - RR]
        Node2_2[Worker Node 5]
        Node2_3[Worker Node 6]
        
        Node2_2 <--> |Internal Peering| Node2_1
        Node2_3 <--> |Internal Peering| Node2_1
        Node2_1 <--> |BGP Uplink| ToR2
    end

    ToR1 <--> CoreRouter1
    ToR1 <--> CoreRouter2
    ToR2 <--> CoreRouter1
    ToR2 <--> CoreRouter2
```

### Architectural Concepts:
1. **Full-Mesh vs. Route Reflectors:** In standard BGP configurations, every node must establish a peering connection with every other node. In a 100-node cluster, this requires 4,950 connections. Calico solves this by dedicating specific nodes as **Route Reflectors (RR)**, aggregating routing updates and broadcasting them to non-reflector nodes.
2. **Top-of-Rack (ToR) Integration:** In on-premises and bare-metal environments, Calico BIRD daemons peer directly with physical ToR switch routers. This enables Pod IPs to be routed natively across the entire datacenter without overlay network encapsulation overhead.
3. **High Availability Routing:** Nodes are connected to redundant ToR switches, using Equal-Cost Multi-Path (ECMP) routing to distribute traffic across parallel uplinks.
