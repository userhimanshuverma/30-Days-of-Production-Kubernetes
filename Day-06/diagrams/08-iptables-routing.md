# 08 - iptables Packet Traversal Path

In `iptables` mode, kube-proxy creates custom chains in the NAT table. Packets entering a node or generated locally traverse these chains to get translated and routed.

## Chain Flowchart

```
Packet entering Node (PREROUTING) or generated locally (OUTPUT)
  │
  ▼
┌────────────────────────────────────────────────────────┐
│ KUBE-SERVICES Chain                                    │
│ Matches Service ClusterIP or External IP / NodePort    │
└────────────────────────────────────────────────────────┘
  │
  ▼ Match: target Service found
┌────────────────────────────────────────────────────────┐
│ KUBE-SVC-XXXXXXXXXXXXXXXX Chain                        │
│ Represents the Service. Uses "statistic" module for    │
│ random load balancing across endpoints.                 │
└────────────────────────────────────────────────────────┘
  │
  ├─► Probability: 33% (if 3 backends)
  │   ▼
  │ ┌────────────────────────────────────────────────────┐
  │ │ KUBE-SEP-YYYYYYYYYYYYYYYY Chain (Endpoint A)      │
  │ │ Performs DNAT to Pod A IP: 10.244.1.5:8080         │
  │ └────────────────────────────────────────────────────┘
  │
  ├─► Probability: 50% (of remaining 67%)
  │   ▼
  │ ┌────────────────────────────────────────────────────┐
  │ │ KUBE-SEP-ZZZZZZZZZZZZZZZZ Chain (Endpoint B)      │
  │ │ Performs DNAT to Pod B IP: 10.244.1.6:8080         │
  │ └────────────────────────────────────────────────────┘
  │
  └─► Probability: 100% (remaining 33%)
      ▼
    ┌────────────────────────────────────────────────────┐
    │ KUBE-SEP-WWWWWWWWWWWWWWWW Chain (Endpoint C)      │
    │ Performs DNAT to Pod C IP: 10.244.2.12:8080        │
    │ └──────────────────────────────────────────────────┘
```

### Low-Level rule examples (from `iptables-save` output)
For a Service named `web-backend-service` with 3 backend pods:
```text
-A KUBE-SERVICES -d 10.96.14.22/32 -p tcp -m comment --comment "default/web-backend-service:http" -j KUBE-SVC-K2G6P76OJUHTNXWS
-A KUBE-SVC-K2G6P76OJUHTNXWS -m statistic --mode random --probability 0.33333333349 -j KUBE-SEP-3F6G7D3E2F1B4A5C
-A KUBE-SVC-K2G6P76OJUHTNXWS -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-9R8Q7P6O5N4M3L2K
-A KUBE-SVC-K2G6P76OJUHTNXWS -j KUBE-SEP-8Z7Y6X5W4V3U2T1S
```

* **Linear Search Penalty**: Because iptables evaluation is sequential, every packet must be evaluated against the rules step-by-step. In a large cluster with 5,000 Services and 20,000 endpoints, a packet might have to evaluate against tens of thousands of rules, creating CPU latency.
* **Statistic Random Balancing**: The iptables `statistic` module distributes traffic by calculating probabilities sequentially.
  * 1st Pod gets chosen with 1/3 (33%) probability.
  * If not chosen, the packet passes to the next rule. The 2nd Pod gets chosen with 1/2 (50%) of the remaining probability (which equals 33% of the original traffic).
  * If not chosen, the packet falls through to the final rule (100% probability), routing to the 3rd Pod.
