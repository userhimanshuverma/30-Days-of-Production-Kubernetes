# 03 - ClusterIP Packet Flow (Internal Service)

`ClusterIP` is the default Service type. It allocates a virtual IP (VIP) from the cluster's service CIDR. This IP is only accessible inside the cluster.

## Packet Interception and DNAT Flow

```
Client Pod (10.244.1.5)
   │
   │ [Dest: 10.96.14.22:80]  (ClusterIP)
   ▼
Host TCP/IP Stack (Worker Node 1)
   │
   ├─► Intercepted by iptables/IPVS Rules (configured by kube-proxy)
   │   │
   │   │  * Randomly selects backend Pod from endpoints (e.g., Pod C)
   │   │  * Performs DNAT (Destination Network Address Translation)
   │   │
   │   ▼
   │ [Dest Rewritten: 10.244.2.12:8080] (Pod C IP)
   ▼
Routing Table (Forward to physical network / tunnel)
   │
   ▼
Worker Node 2 (Host NIC)
   │
   ▼
Backend Pod C (10.244.2.12)
```

## Detailed Path Visualized

```mermaid
graph LR
    %% Styling
    classDef pod fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef rules fill:#313244,stroke:#f9e2af,stroke-width:2px,color:#cdd6f4;
    classDef node fill:#181825,stroke:#a6e3a1,stroke-dasharray: 3 3,stroke-width:2px,color:#cdd6f4;

    subgraph Node1 [Worker Node 1]
        SrcPod[Client Pod <br> IP: 10.244.1.5]:::pod
        Rules[iptables / IPVS NAT Rules <br> Intercept 10.96.14.22:80 <br> Apply DNAT to 10.244.2.12:8080]:::rules
        
        SrcPod -->|1. HTTP Request| Rules
    end

    subgraph Node2 [Worker Node 2]
        DstPod[Backend Pod C <br> IP: 10.244.2.12]:::pod
    end

    Rules -->|2. DNATed Packet sent over network| DstPod
    DstPod -->|3. Return Packet (re-SNATed on Node 1)| SrcPod

    class Node1 node;
    class Node2 node;
```

### Critical Rules
* **No pinging ClusterIP**: Since ClusterIP is a virtual IP that only exists in iptables/IPVS rules, it does not respond to ICMP ping requests. Do not try to `ping` a ClusterIP to check if it's working; use `curl` or `nc` instead.
* **Client-side Load Balancing**: The translation occurs on the originating node (Worker Node 1 in the diagram above). The client node selects the destination pod and executes DNAT before sending the packet onto the network.
* **Return Path**: When the backend pod replies, the host network stack on the originating node automatically reverses the NAT translation (SNAT), replacing the source Pod IP with the ClusterIP, so the client pod thinks it is communicating with a single stable service.
