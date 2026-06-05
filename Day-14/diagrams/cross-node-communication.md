# Cross-Node Packet Communication Flow

This sequence diagram traces the step-by-step path of a single packet as it crosses kernel-space and physical interface boundaries from a source Pod on Node 1 to a destination Pod on Node 2.

```mermaid
sequenceDiagram
    autonumber
    participant PodA as Pod A Namespace [eth0]
    participant Host1Veth as Node 1 veth [caliXXX]
    participant Host1Net as Node 1 Routing & VXLAN
    participant Eth1 as Node 1 Physical NIC
    participant Eth2 as Node 2 Physical NIC
    participant Host2Net as Node 2 Routing & VXLAN
    participant Host2Veth as Node 2 veth [caliYYY]
    participant PodB as Pod B Namespace [eth0]

    PodA->>Host1Veth: 1. Egress packet out of Container eth0
    Host1Veth->>Host1Net: 2. Arrives at host root network namespace
    Note over Host1Net: Route check: 10.244.2.10 is remote.<br/>Gateway is Node 2 (192.168.1.20) via vxlan.calico.
    Host1Net->>Host1Net: 3. Encapsulate original IP packet in Outer UDP/VXLAN header
    Host1Net->>Eth1: 4. Route outer packet to physical adapter
    Eth1->>Eth2: 5. Transmit packet across physical network switch fabric
    Eth2->>Host2Net: 6. Receive packet, verify UDP Port 4789
    Host2Net->>Host2Net: 7. Decapsulate packet, exposing inner Pod IP packet
    Note over Host2Net: Route check: 10.244.2.10 is local.<br/>Delivered via local interface caliYYY.
    Host2Net->>Host2Veth: 8. Forward un-encapsulated packet to target veth
    Host2Veth->>PodB: 9. Ingress packet into Container eth0
```

### Protocol Plumbing Steps:
1. **Network Namespace Boundary:** The packet crosses the container-to-host border via a virtual ethernet pipe (`veth`).
2. **Host Routing Decision:** The host Linux kernel inspects the destination IP against its routing table (`ip route`).
3. **Encapsulation Device:** Traffic is directed to the overlay network device (e.g. `vxlan.calico`), which dynamically appends outer IP headers.
4. **Physical Network:** Standard routers and switches in the physical datacenter only see the outer host node IPs, routing the packet like standard host-to-host traffic.
5. **Decapsulation and Local Delivery:** The receiving node processes the incoming outer packet, unpacks the original payload, and directs it to the correct virtual interface in the target container.
