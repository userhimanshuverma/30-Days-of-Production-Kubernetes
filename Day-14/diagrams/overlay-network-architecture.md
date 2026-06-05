# Overlay Network Architecture

This diagram visualizes how physical worker nodes encapsulate Pod-to-Pod traffic to route packets across nodes that are on different physical networks.

```mermaid
graph TD
    subgraph Host1 [Worker Node 1 - IP: 192.168.1.10]
        PodA[Pod A - 10.244.1.5]
        PodANic[eth0] <--> PodA
        Node1Kernel[Node 1 Kernel Engine] <--> PodANic
        VXLANDev1[VXLAN Device: vxlan.calico] <--> Node1Kernel
    end

    subgraph Host2 [Worker Node 2 - IP: 192.168.1.20]
        PodB[Pod B - 10.244.2.10]
        PodBNic[eth0] <--> PodB
        Node2Kernel[Node 2 Kernel Engine] <--> PodBNic
        VXLANDev2[VXLAN Device: vxlan.calico] <--> Node2Kernel
    end

    subgraph PacketFlow [Packet Journey: Encapsulation & Decapsulation]
        Orig[Original Pod IP Packet<br/>Src: 10.244.1.5 | Dst: 10.244.2.10]
        Enc[Encapsulated VXLAN Frame<br/>Outer Src: 192.168.1.10 | Outer Dst: 192.168.1.20<br/>UDP Port: 4789 | VXLAN VNI: 4096<br/>Inner Src: 10.244.1.5 | Inner Dst: 10.244.2.10]
    end

    PodA ==> |Sends original packet| Node1Kernel
    Node1Kernel ==> |Redirects to VXLAN| VXLANDev1
    VXLANDev1 ==> |Wraps packet with VXLAN + UDP headers| Orig
    Orig -.-> Enc
    Enc ==> |Transmits across physical fabric| VXLANDev2
    VXLANDev2 ==> |Strips outer host headers| Node2Kernel
    Node2Kernel ==> |Delivers inner packet| PodB
```

### Encapsulation Formats:

#### VXLAN Header Detail (Layer 2 over Layer 4 UDP)
```
┌─────────────────┬─────────────────┬─────────────────┬─────────────────┬───────────┐
│ Outer Ethernet  │ Outer IP Header │ Outer UDP (4789)│ VXLAN VNI Flags │ Inner IP  │
│ Dst Node2 MAC   │ Src Node1 IP    │ Src Port: Custom│ VNI ID: 4096    │ Src Pod A │
│ Src Node1 MAC   │ Dst Node2 IP    │ Dst Port: 4789  │                 │ Dst Pod B │
└─────────────────┴─────────────────┴─────────────────┴─────────────────┴───────────┘
```

#### IP-in-IP Header Detail (Layer 3 over Layer 3 IP)
```
┌─────────────────┬─────────────────┬─────────────────┬───────────┐
│ Outer Ethernet  │ Outer IP Header │ Inner IP Header │ Payload   │
│ Dst Node2 MAC   │ Src Node1 IP    │ Src Pod A IP    │ (Data)    │
│ Src Node1 MAC   │ Dst Node2 IP    │ Dst Pod B IP    │           │
└─────────────────┴─────────────────┴─────────────────┴───────────┘
```
* Note: IP-in-IP uses Protocol 4 (IPv4 encapsulation) in the Outer IP Header.
* VXLAN has higher network overhead (50 bytes) than IP-in-IP (20 bytes), but provides better compatibility across Cloud Fabrics and Layer 2 virtual ethernet bridging.
