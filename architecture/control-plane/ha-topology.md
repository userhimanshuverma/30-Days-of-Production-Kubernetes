# Control Plane High Availability Topology

This document details the architectural options, quorum calculations, and load balancing configurations for high-availability Kubernetes control planes.

---

## 🏛️ Stacked vs External etcd Topologies

### 1. Stacked etcd Topology (Recommended for ease of management)
In a stacked topology, each control plane node runs local instances of `kube-apiserver`, `kube-scheduler`, `kube-controller-manager`, and the `etcd` server.

```
┌─────────────────────────────────┐   ┌─────────────────────────────────┐
│       Control Plane Node 1      │   │       Control Plane Node 2      │
│  ┌──────────┐     ┌──────────┐  │   │  ┌──────────┐     ┌──────────┐  │
│  │apiserver │ ─── │etcd (1)  │──┼───┼──│apiserver │ ─── │etcd (2)  │  │
│  └──────────┘     └────┬─────┘  │   │  └──────────┘     └────┬─────┘  │
└────────────────────────┼────────┘   └────────────────────────┼────────┘
                         │                                     │
                         └──────────────────┬──────────────────┘
                                            ▼
                              ┌───────────────────────────┐
                              │       etcd Peering        │
                              └───────────────────────────┘
```

*   **Pros**: Simple configuration, requires fewer physical or virtual machines, easy storage tracking.
*   **Cons**: Coupling of compute resources; if a control plane node runs out of memory, both the API server and etcd instance fail.

### 2. External etcd Topology (Recommended for large-scale enterprise environments)
The etcd cluster runs on dedicated machines, isolated from the nodes running the stateless control plane API components.

*   **Pros**: Separation of concerns, etcd performance is insulated from API query load spikes.
*   **Cons**: Double the server overhead (minimum of 3 control plane nodes + 3 etcd nodes).

---

## 🔢 Quorum Calculations
Etcd uses the Raft algorithm for consensus. To make progress, a majority of nodes (quorum) must be available:

$$Q = \lfloor N/2 \rfloor + 1$$

Where:
*   $N$ is the total number of members in the etcd cluster.
*   $Q$ is the minimum number of active nodes required to operate.

### Failover Resiliency Reference Table
| Cluster Size ($N$) | Quorum ($Q$) | Max Tolerated Failures |
| :---: | :---: | :---: |
| 1 | 1 | 0 |
| 2 | 2 | 0 (No benefit, do not run even numbers) |
| 3 | 2 | 1 |
| 4 | 3 | 1 (Adding a 4th node decreases efficiency) |
| 5 | 3 | 2 |
| 7 | 4 | 3 |

---

## ⚙️ Load Balancing API Servers
Stateless `kube-apiserver` endpoints are fronted by a Layer 4 Load Balancer (HAProxy, NGINX, or cloud LB) forwarding TCP traffic on port `6443` to the control plane nodes.

### Sample HAProxy Configuration Snippet
```haproxy
frontend k8s-api
    bind 192.168.1.100:6443
    mode tcp
    option tcplog
    default_backend k8s-api-masters

backend k8s-api-masters
    mode tcp
    option tcplog
    option httpchk GET /healthz
    http-check expect status 200
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 3 slowstart 60s maxconn 250 maxqueue 256 weight 100
    server master-1 192.168.1.10:6443 check check-ssl verify none
    server master-2 192.168.1.11:6443 check check-ssl verify none
    server master-3 192.168.1.12:6443 check check-ssl verify none
```
