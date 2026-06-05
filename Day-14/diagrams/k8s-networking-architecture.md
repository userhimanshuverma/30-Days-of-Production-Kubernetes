# Kubernetes Networking Architecture

This diagram illustrates the comprehensive structural architecture of Kubernetes networking, showing node boundaries, virtual namespaces, interface connections, and the control loop elements.

```mermaid
graph TB
    subgraph ControlPlane [Kubernetes Control Plane]
        APIServer[kube-apiserver]
        CoreDNS[CoreDNS Service]
    end

    subgraph Node1 [Worker Node 1]
        Kubelet1[kubelet]
        KubeProxy1[kube-proxy]
        CNI1[CNI Plugin: Calico Felix]
        
        subgraph PodA [Pod A Namespace]
            eth0A[eth0: 10.244.1.5]
            AppA[Application Container]
        end

        vethA[cali_a83f9e] <--> eth0A
        KubeProxy1 -.-> |iptables/IPVS Rules| Node1Kernel[Node 1 Linux Kernel]
        CNI1 -.-> |Configures routes/policy| Node1Kernel
        vethA <--> Node1Kernel
        PhysNic1[Physical NIC: 192.168.1.10] <--> Node1Kernel
    end

    subgraph Node2 [Worker Node 2]
        Kubelet2[kubelet]
        KubeProxy2[kube-proxy]
        CNI2[CNI Plugin: Calico Felix]

        subgraph PodB [Pod B Namespace]
            eth0B[eth0: 10.244.2.10]
            AppB[Application Container]
        end

        vethB[cali_b74d12] <--> eth0B
        KubeProxy2 -.-> |iptables/IPVS Rules| Node2Kernel[Node 2 Linux Kernel]
        CNI2 -.-> |Configures routes/policy| Node2Kernel
        vethB <--> Node2Kernel
        PhysNic2[Physical NIC: 192.168.1.20] <--> Node2Kernel
    end

    %% Network Fabric
    PhysNic1 <==> |Physical Fabric / Underlay| PhysNic2
    Kubelet1 ==> |Sync Pod States| APIServer
    Kubelet2 ==> |Sync Pod States| APIServer
    CoreDNS -.-> |DNS Resolution| PodA
    CoreDNS -.-> |DNS Resolution| PodB
```

### Architectural Concepts:
1. **Network Namespaces (`netns`):** Each Pod has its own isolated network stack (interfaces, routing table, firewall rules).
2. **Virtual Ethernet (`veth`):** Act as physical patches between the isolated container namespace and the host's root namespace.
3. **Kube-Proxy:** Operates in the background, writing firewall rules (`iptables` or `IPVS`) inside the host's kernel to direct service VIP traffic to target Pods.
4. **Felix (Calico CNI):** Programs routing and firewall rules locally on each node based on API server configuration states.
