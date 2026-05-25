# ⚡ Senior-Level Production Notes: Kubernetes Internals at Scale

Operating Kubernetes in high-scale enterprise environments (thousands of nodes, tens of thousands of pods) reveals bottlenecks that do not show up in dev environments. These notes compile hard-learned operational realities of managing the Kubernetes control plane.

---

## 💾 1. etcd Scaling & Operational Realities

### The 8GB Storage Hard-Limit
* **The DB size limit:** By default, etcd enforces a conservative **2GB database quota** (configurable via `--quota-backend-bytes` up to a **hard-limit of 8GB**).
* **What happens when the quota is exceeded?** etcd triggers a cluster-wide `NOSPACE` alarm, placing the database in **read-only mode**. All writes (including lease updates, pod status patches, and deployments) fail.
* **Production mitigation:**
  * Configure aggressive compaction policies: set API Server flags `--etcd-compaction-interval=5m`.
  * Run periodic defragmentation via cron job inside the control plane:
    ```bash
    etcdctl defrag --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key
    ```

### IOPS & Disk Fdatasync Latency
* etcd writes WAL files using synchronous writes (`fdatasync`).
* **Disk requirements:** SSD or NVMe drives are mandatory. Standard HDDs or slow network storage (like AWS EBS gp2/gp3 with low baseline IOPS) will fail to replicate transactions quickly enough under write spikes, causing Raft leader elections to fail.
* **Telemetry metric to watch:** `etcd_disk_wal_fdatasync_duration_seconds`. The 99th percentile of this metric **must be under 10ms**. If it exceeds 10ms, your etcd cluster is experiencing disk bottlenecks.

---

## 🚦 2. API Server Bottlenecks & APF (API Priority & Fairness)

### Request Throttling Limits
In older versions, the API Server throttled traffic using two crude flags:
* `--max-requests-in-flight` (default: 400)
* `--max-mutating-requests-in-flight` (default: 200)
If incoming requests exceeded these numbers, the API Server rejected them with an HTTP 429.

### Modern APF (API Priority and Fairness)
Modern Kubernetes clusters use APF by default. It categorizes requests into "Priority Levels" (e.g., `system-leader-election`, `workload-high`, `workload-low`, `catch-all`) and allocates seats (execution concurrency) to them.
* **The risk:** A misconfigured third-party controller (e.g., a buggy monitoring daemon or CI pipeline run amok) can saturate the `catch-all` or `workload-low` queues. APF isolates this traffic, ensuring that Kubelet heartbeats and leader elections (`system-leader-election`) proceed without delay.
* **Production tuning:** Never disable APF. Monitor `apiserver_flowcontrol_rejected_requests_total` to verify if client traffic is being dropped due to APF queue overflows.

---

## 🗓️ 3. Scheduler Performance Challenges

### Linear Scheduling Degradation
* In its default configuration, the scheduler evaluates **every node** in the cluster during the filtering phase to find the best node.
* In a 5,000-node cluster, running this evaluation for every pod creates high scheduling latency, blocking large scale-ups.

### Tuning: percentageOfNodesToScore
* The `--percentage-of-nodes-to-score` parameter (default: dynamic, ranging from 50% in small clusters to 5% in clusters with thousands of nodes) instructs the scheduler to stop filtering once it finds a sufficient percentage of fit nodes.
* **The trade-off:** Lowering this value speeds up scheduling but can result in suboptimal placement decisions (e.g., scheduling a pod on a node with 70% CPU load instead of a node with 10% load, simply because it stopped scanning early).

---

## 🔄 4. Controller Backpressure & Watch API Scaling

### Informer Memory Bloat
* Every controller maintains an Informer cache.
* If a controller watches all Pods and ConfigMaps, it caches them in its local memory.
* **The danger:** Third-party operators written in Go that cache entire namespaces can easily consume gigabytes of RAM. If you run 20 different controller managers/admission webhooks, they will duplicate this memory footprint across the cluster.
* **Production tuning:** Use **SharedInformers** to share caches between controllers running in the same process, or use field/label selectors to restrict the informer's watch scope to only relevant namespaces.

### Watch Connection Re-establishment Storms
* When the API Server undergoes a rolling update, thousands of Kubelets and controllers temporarily lose their Watch connections.
* When they reconnect, they will attempt to stream updates. If they did not keep track of their last read `resourceVersion`, they will request a full list of all resources instead of an incremental watch.
* **List Storm:** This triggers a "List Storm", causing memory utilization on the API Server to spike instantly, often triggering Out-Of-Memory (OOM) crashes.
* **Production prevention:** Ensure all custom code, client libraries, and operators implement exponential backoff on reconnection and utilize incremental watches using the correct `resourceVersion`.

---

## 🤝 5. Control Plane HA and Split-Brain Risks

### Distributed Active-Passive Components
While the API Server is stateless and runs active-active behind a load balancer, components like the `kube-controller-manager` and `kube-scheduler` are **active-passive**.
* **Leader Election via Leases:** Only one replica of the controller manager can act as the leader. The leader maintains a lock (a `Lease` object in the `kube-system` namespace) by constantly updating its heartbeat.
* **Network Partition Scenario:** If the active leader experiences a network split where it can communicate with worker nodes but not with the API Server, it will fail to renew its Lease. A passive node will detect the lease expiration, assume leadership, and start reconciling.
* **Split-Brain Risk:** If the partitioned master node recovers and still believes it is the leader, both controllers might issue conflicting commands to the worker nodes. Kubernetes mitigates this using optimistic concurrency control in etcd: every write is bound to a `resourceVersion`. If a controller attempts to modify an object using stale data, the API Server rejects the write, preventing state corruption.
