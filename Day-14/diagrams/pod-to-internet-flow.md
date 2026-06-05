# Pod-to-Internet Traffic Flow

This diagram details how a Pod sends outgoing requests to the public Internet, and how the host node uses IP Masquerading (SNAT) to route the traffic using its own physical IP.

```mermaid
graph TD
    subgraph ClusterNode [Worker Node - IP: 192.168.1.10]
        Pod[Pod - IP: 10.244.1.5]
        veth[veth interface]
        
        subgraph KernelRouting [Kernel Routing Engine]
            RouteCheck{Destination is External?<br/>e.g., 8.8.8.8}
            MasqRule[iptables POSTROUTING<br/>-j MASQUERADE]
        end
        
        PhysNIC[Host Physical NIC - IP: 192.168.1.10]
    end

    Internet((Public Internet))

    Pod ==> |Request to 8.8.8.8| veth
    veth ==> RouteCheck
    RouteCheck ==> |Yes| MasqRule
    MasqRule ==> |SNAT: Replace Src IP with Host IP| PhysNIC
    PhysNIC ==> |Transmitted Packet<br/>Src: 192.168.1.10 | Dst: 8.8.8.8| Internet
```

### Source NAT (SNAT) Mechanics:
1. **Private CIDR Limitations:** Pod IP ranges (e.g. `10.244.0.0/16`) are private and cannot be routed on the public internet.
2. **Outbound Detection:** When a Pod initiates a connection to an external address (like `8.8.8.8`), the host kernel detects that the target destination lies outside the local Pod IP blocks.
3. **IP Masquerading (MASQUERADE):** The kernel replaces the source IP field of the packet (`10.244.1.5`) with the host's physical IP address (`192.168.1.10`). It stores this mapping in its connection tracking state (`conntrack`).
4. **Return Paths:** When the external server responds to `192.168.1.10`, the host kernel checks its `conntrack` tables, restores the destination IP back to `10.244.1.5`, and forwards the packet into the Pod's virtual interface.
