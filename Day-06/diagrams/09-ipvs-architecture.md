# 09 - IPVS (IP Virtual Server) Routing Architecture

IPVS is designed for high-performance load balancing in large-scale Kubernetes clusters. Unlike iptables, which evaluates rules sequentially ($O(N)$ complexity), IPVS uses kernel hash tables, providing near-constant lookup time ($O(1)$ complexity) regardless of the number of Services.

## Hash Table Routing vs. Linear Chains

```mermaid
graph TD
    %% Styling
    classDef packet fill:#181825,stroke:#f38ba8,stroke-width:2px,color:#cdd6f4;
    classDef lookup fill:#313244,stroke:#f9e2af,stroke-width:2px,color:#cdd6f4;
    classDef dest fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;

    Packet[Incoming Packet <br> Dest IP: 10.96.14.22:80]:::packet --> IPVS_Engine[IPVS Kernel Module]
    
    subgraph HashLookup [IPVS Hash Table Lookup - O(1) Complexity]
        IPVS_Engine --> Hash[Hash Table Index]:::lookup
        Hash -->|Key Match: 10.96.14.22:80| TargetList[Backend list]:::lookup
    end

    TargetList -->|Algorithm: Round-Robin / Least Conn| SelectedPod[Pod C IP: 10.244.2.12:8080]:::dest
```

### IPVS vs. iptables Feature Comparison Table

| Attribute | iptables Mode | IPVS Mode |
|---|---|---|
| **Lookup Time** | $O(N)$ (linear scanning of chains) | $O(1)$ (direct hash table lookup) |
| **Scaling Limit** | Noticeable CPU penalty after ~2,000 Services | Scales easily to 10,000+ Services |
| **Load Balancing Algorithms** | Random (via statistics module) | Round-Robin (rr), Least Connection (lc), Destination Hashing (dh), Source Hashing (sh), Shortest Expected Delay (sed) |
| **Dummy Interfaces** | No virtual interface created | Creates a dummy network interface (`kube-ipvs0`) containing all ClusterIP addresses |
| **Dependencies** | Default in Linux kernel | Requires kernel IPVS modules to be pre-loaded on host nodes |

### Operational Takeaway
For smaller clusters (< 1,000 Services), `iptables` is perfect and requires zero setup. For large enterprise environments (thousands of services and endpoints), `IPVS` mode must be enabled in `kube-proxy` config to prevent node CPU starvation caused by iptables rule updates and lookup overhead.
