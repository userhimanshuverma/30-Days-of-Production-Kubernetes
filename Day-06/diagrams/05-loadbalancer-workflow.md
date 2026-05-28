# 05 - LoadBalancer Service Workflow

A `LoadBalancer` Service builds on top of ClusterIP and NodePort. It requests an external cloud load balancer (e.g., AWS NLB/ALB, Google Cloud LB) to route internet/intranet traffic to the cluster.

## Architecture & Traffic Flow (externalTrafficPolicy Comparison)

```mermaid
graph TD
    %% Styling
    classDef client fill:#181825,stroke:#f38ba8,stroke-width:2px,color:#cdd6f4;
    classDef lb fill:#313244,stroke:#f9e2af,stroke-width:2px,color:#cdd6f4;
    classDef node fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;
    classDef pod fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef empty fill:#000000,stroke:#000000,color:#cdd6f4;

    subgraph ClusterMode [Option A: externalTrafficPolicy: Cluster (Default)]
        ClientA[Client]:::client --> LB_Cluster[Cloud Load Balancer]:::lb
        LB_Cluster -->|Distributes to all nodes| NodeA1[Node 1 <br> Has backend Pod]:::node
        LB_Cluster -->|Distributes to all nodes| NodeA2[Node 2 <br> No backend Pod]:::node
        
        NodeA1 -->|Local routing| PodA1[Backend Pod A]:::pod
        NodeA2 -->|Cross-Node SNAT Hop| NodeA1 --> PodA1
    end

    subgraph LocalMode [Option B: externalTrafficPolicy: Local]
        ClientB[Client]:::client --> LB_Local[Cloud Load Balancer]:::lb
        LB_Local -->|Directs ONLY to nodes with pods| NodeB1[Node 1 <br> Has backend Pod <br> Health Check: UP]:::node
        LB_Local -.-x|Does NOT send traffic| NodeB2[Node 2 <br> No backend Pod <br> Health Check: DOWN]:::node
        
        NodeB1 -->|Direct L4 routing| PodB1[Backend Pod B]:::pod
    end
```

### Flow Breakdown

#### Option A: `externalTrafficPolicy: Cluster`
1. **CCM (Cloud Controller Manager)**: Automatically provisions a Load Balancer pointing to all nodes on the designated NodePort.
2. **Load Balancer Health Check**: Queries a basic HTTP health check on all nodes. All nodes return `200 OK` because they can route traffic internally.
3. **Traffic Distribution**: Traffic is balanced equally across all nodes.
4. **The Hop**: If traffic hits a node without a local replica of the Pod, the node performs SNAT and forwards the packet to a node with a Pod, causing latency and losing the Client IP.

#### Option B: `externalTrafficPolicy: Local`
1. **Local Node Checking**: The Kubelet exposes a special health check port (default 10256) on every node. 
2. **Health Check Logic**: 
   * Node 1 has a running Pod -> returns `200 OK`.
   * Node 2 has no Pod -> returns `503 Service Unavailable`.
3. **Load Balancer Routing**: The Cloud Load Balancer detects Node 2 is unhealthy and removes it from the routing targets.
4. **Zero Hops**: Traffic only lands on nodes with running Pods. The node performs DNAT directly to the local Pod without SNAT.
5. **Benefits**: Preserves the original Client IP and removes extra network hops.
6. **Risk**: If Node 1 has 1 Pod and Node 2 has 3 Pods, Node 1 receives 50% of the total load balancer traffic, overloading its single Pod. Ensure even replica distribution (using Pod Anti-Affinity) when using `externalTrafficPolicy: Local`.
