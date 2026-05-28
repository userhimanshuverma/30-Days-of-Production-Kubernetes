# 07 - kube-proxy Internals

`kube-proxy` runs on every worker node as a DaemonSet. It does not act as an inline proxy (which would be a major performance bottleneck); instead, it acts as a controller that configures the kernel's packet-filtering and NAT rules.

## Control Loop Architecture

```mermaid
graph TD
    %% Styling
    classDef control fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef kp fill:#313244,stroke:#f9e2af,stroke-width:2px,color:#cdd6f4;
    classDef kernel fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;

    APIServer[kube-apiserver]:::control -->|1. Event Stream: Services & Endpoints| KubeProxy[kube-proxy DaemonSet <br> running on Node]:::kp

    subgraph NodeHost [Worker Node Operating System]
        KubeProxy -->|2. Program Rules via Netlink / iptables-restore| Kernel[Linux Kernel Data Path]:::kernel
        
        subgraph KernelDataPath [Kernel Space]
            Kernel -->|Mode A| iptables[iptables Rules <br> L4 Netfilter chains]:::kernel
            Kernel -->|Mode B| IPVS[IPVS Tables <br> L4 Load Balancing Kernel Module]:::kernel
        end
    end

    IncomingPacket[Incoming Packet] -->|3. Kernel Intercepts & DNATs| KernelDataPath
    KernelDataPath -->|4. Forward to Pod| TargetPod[Target Backend Pod]
```

### Execution Loop Details
1. **Watch Loop**: kube-proxy starts a watch loop against the API server to catch creations, updates, or deletions of `Service` and `EndpointSlice` objects.
2. **Reconciliation**: When an event occurs, kube-proxy updates its memory cache and triggers a reconciliation cycle.
3. **Data Path Programming**: 
   * **iptables Mode**: Translates all services into sequential iptables rules chains, replacing the entire rule-set in the kernel space using a bulk command.
   * **IPVS Mode**: Calls netlink interfaces to add IPVS virtual servers and bind backend pod endpoints as target servers.
4. **Traffic Path**: When packets arrive at the host network interfaces, the kernel processes them via the programmed routing rules directly, ensuring high throughput.
