# Container Network Interface (CNI) Workflow

This diagram outlines how Kubelet invokes the CNI plugin on Pod initialization and deletion.

```mermaid
sequenceDiagram
    autonumber
    participant APIServer as Kube-API Server
    participant Kubelet as Kubelet Daemon
    participant CRI as Container Runtime (containerd)
    participant CNI as CNI Plugin (Calico/Flannel)
    participant Kernel as Linux Kernel

    APIServer->>Kubelet: Schedule Pod to Node
    Kubelet->>CRI: Create Sandbox Container
    CRI->>Kernel: Create Linux Network Namespace (netns)
    CRI->>CNI: Execute Plugin: ADD (CNI_ARGS, netns path)
    Note over CNI: Read /etc/cni/net.d/ configurations
    CNI->>CNI: Request IP from IPAM Plugin (Host-Local/Calico)
    CNI->>Kernel: Create veth pair (vethXXXX <-> eth0)
    CNI->>Kernel: Move eth0 inside Pod Namespace
    CNI->>Kernel: Configure eth0 (IP Address, MAC, Default Route)
    CNI->>Kernel: Configure host routing table rules
    CNI-->>CRI: Return JSON result (Success, IP allocated)
    CRI->>Kubelet: Sandbox Ready
    Kubelet->>APIServer: Pod Status: Running (with IP)
```

### Key Lifecycle Operations:
* **`ADD` Execution:** Invoked when starting a container. The runtime passes container ID, network namespace path, network configuration JSON, and container-specific arguments.
* **IPAM Delegation:** CNI plugins separate network routing from IP address management. They delegate IP allocation to specialized IPAM plugins (e.g., allocating a slice of a CIDR).
* **`DEL` Execution:** Invoked when destroying a container. It triggers CNI to free the IP address back to the pool and delete the virtual ethernet interfaces from the host.
