# Calico Component Architecture

This diagram illustrates how Calico's control plane and data plane components communicate to configure routing and policy enforcement across a Kubernetes cluster.

```mermaid
graph TB
    subgraph ControlPlane [Control Plane / API Server]
        APIServer[kube-apiserver]
        Datastore[(Kubernetes custom-resources/etcd)]
        APIServer <--> Datastore
    end

    subgraph Node1 [Worker Node 1]
        Felix1[Calico Felix Daemon]
        BIRD1[BIRD BGP Routing Daemon]
        Confd1[confd Config Engine]
        Kernel1[Linux Kernel Data Plane]
        
        Felix1 ==> |Directly updates| Kernel1
        Confd1 ==> |Writes BGP templates| BIRD1
        BIRD1 <==> |Peers Route Updates| Kernel1
    end

    subgraph Node2 [Worker Node 2]
        Felix2[Calico Felix Daemon]
        BIRD2[BIRD BGP Routing Daemon]
        Confd2[confd Config Engine]
        Kernel2[Linux Kernel Data Plane]
        
        Felix2 ==> |Directly updates| Kernel2
        Confd2 ==> |Writes BGP templates| BIRD2
        BIRD2 <==> |Peers Route Updates| Kernel2
    end

    subgraph ScaleLayer [Typha Fan-out Proxy - Optional]
        Typha[Calico Typha Daemon]
    end

    %% Sync Paths
    APIServer <==> |Sync state| Typha
    Typha <==> |Distribute events| Felix1
    Typha <==> |Distribute events| Felix2
    
    %% BGP peering
    BIRD1 <==> |BGP Peer-to-Peer Routing Mesh| BIRD2
```

### Components Decoded:
1. **Felix:** The brain of Calico on each host. It programs IP routes, configures network interfaces, and writes iptables or eBPF chains to enforce Network Policies.
2. **BIRD:** A dynamic routing daemon that exchanges IP routing information with BIRD on other nodes using BGP, ensuring nodes know how to reach remote Pod CIDRs directly.
3. **Confd:** Listens to the Calico datastore for changes in network settings, generating configuration files for BIRD dynamically.
4. **Typha:** Sits between Felix and the Kubernetes API server in large clusters. Felix agents query Typha instead of the API server directly, reducing the connection load on the Kubernetes control plane.
5. **Datastore:** Calico stores its configurations (like IP Pools and Profile policies) inside the standard Kubernetes database (`etcd`) via Custom Resource Definitions (CRDs).
