# 📓 Lessons Learned Designing Large-Scale Kubernetes Platforms

This document compiles operational wisdom, capacity guidelines, and analyses of real production outages experienced while managing large-scale enterprise Kubernetes clusters.

---

## 1. Managed vs. Self-Managed Control Planes: The Architectural Trade-offs

SRE teams face a choice: deploy Kubernetes via managed services (EKS, GKE, AKS) or bootstrap self-managed clusters (kubeadm, kops, kubespray) on raw VMs.

| Consideration | Managed (EKS/GKE) | Self-Managed (kubeadm/VMs) |
| :--- | :--- | :--- |
| **Operational Burden** | Very Low. Cloud provider manages etcd scaling, node updates, and control plane backups. | Extremely High. SRE team must manage etcd backup policies, cluster upgrades, and OS security patching. |
| **Control Plane Customization**| Low. Limited to flags supported by the provider. | Complete. Full access to modify api-server configurations, custom schedulers, and etcd settings. |
| **SLA & Cost** | Cloud provider guarantees 99.9% uptime for a nominal fee ($0.10/hr). | SRE team guarantees SLA. Higher VM costs if running dedicated etcd/master nodes. |
| **Integration** | Automated integrations with Cloud IAM, KMS, and Cloud Storage providers. | Manual integration of CSI/CNI plugins and custom cloud-controller-managers. |

---

## 2. Capacity Planning & Scale Limits

To prevent control plane overload and node scheduling bottlenecks, apply the following cluster limits:

* **Pod Sizing Limits:** Avoid running more than **110 pods per worker node** (by default) or **250 pods** (if using large nodes). High pod counts saturate the Kubelet's PLEG loop, causing nodes to flap between `Ready` and `NotReady`.
* **Namespace Sizing:** Keep the total number of namespaces under **5,000** per cluster. A high namespace count slows down service controller operations and increases search times for Kubernetes API queries.
* **IP Address Allocation:** In environments using VPC-native routing (like EKS), each pod consumes a secondary IP from the node's subnet. A `/24` subnet (254 IPs) can be exhausted by a single large node pool, blocking new pods from spawning with `FailedCreatePodSandBox` errors.

---

## 3. Real Production Outage Analyses

### Incident 1: The etcd Fsync Latency Cascading Outage
* **Symptoms:** Cluster became unresponsive. Commands like `kubectl get nodes` timed out. Workloads were healthy, but no new pods could schedule or scale.
* **Root Cause:** A heavy write-intensive application (logging system) was accidentally scheduled onto the master nodes, sharing the same physical disk as the etcd data directory. This saturated disk I/O, driving etcd disk commit latency past 1.5 seconds.
* **Cascading Effect:** etcd missed its Raft heartbeat window, triggering continuous leader election loops. Because etcd was electing new leaders, the API server rejected incoming mutations and dropped connections.
* **Resolution:** Master nodes were isolated onto dedicated compute instances. The etcd directory was mapped to dedicated NVMe SSD volumes with strict IOPS allocations.
* **Prevention:** Run etcd on dedicated node pools. Use disk metrics (like `etcd_disk_wal_fsync_duration_seconds`) to alert if write latency exceeds 15ms.

---

### Incident 2: DNS Conntrack Saturation during Traffic Spike
* **Symptoms:** High HTTP 504 gateway timeout rates on frontend workloads during a flash sale. Applications logged `dial tcp: lookup backend-svc on 10.96.0.10:53: read udp: i/o timeout`.
* **Root Cause:** The cluster was using CoreDNS with default UDP network traffic rules. Worker nodes hit Linux kernel connection tracking limits (`nf_conntrack`), dropping UDP DNS queries.
* **Resolution:**
  1. Deployed `NodeLocal DNSCache` as a DaemonSet to handle DNS queries locally on each node using cache buffers.
  2. Modified CoreDNS configurations to use TCP instead of UDP for external DNS forwards.
* **Prevention:** Run NodeLocal DNSCache on all clusters running over 50 pods or processing high request volumes.
