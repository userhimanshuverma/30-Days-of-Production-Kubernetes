# 📝 Day 3 Architectural Deep Dive: Kubernetes Internals

This note guide covers the low-level mechanics of the Kubernetes control plane and worker node agents. It is designed for platform engineers and architects who need to understand how the system functions under high load or during partial failure states.

---

## 🏛️ The API Server Architecture (`kube-apiserver`)

The `kube-apiserver` is the REST-based central hub of the control plane. It is a stateless server running an HTTP server (typically listening on port 6443) that handles JSON/YAML payloads over HTTP/gRPC.

### The Request Pipeline
When a request hits `/api/v1/namespaces/default/pods`, it traverses a strict synchronous sequence of handlers:

```
[Request] ➡️ HTTP Handler Chain ➡️ AuthN ➡️ AuthZ ➡️ Admission Control ➡️ Validation ➡️ etcd Store
```

#### 1. HTTP Handler Chain
First, the request is decoded, parsed, and logged. A set of filters (handlers) are applied:
* **Rate Limiting:** Employs APF (API Priority and Fairness) to classify requests into flows and queues them, protecting the control plane from runaway clients.
* **Timeout:** Enforces standard timeouts to prevent slow-loris connection exhausts.
* **CORS & Headers:** Sets basic HTTP headers.

#### 2. Authentication (AuthN)
The API Server loops through configured authentication plugins. The first one to successfully authenticate the user stops the evaluation. If all fail, the request returns a `401 Unauthorized`.
* **X.509 Client Certificates:** The API server validates the client cert using the CA certificate (`--client-ca-file`). The certificate's Common Name (CN) is parsed as the username, and Organization (O) fields represent groups.
* **OpenID Connect (OIDC):** Authenticates JWT tokens issued by external IDPs (e.g., Okta, Keycloak, Dex).
* **Service Account Tokens:** Signed JWT tokens stored as secrets or projected volumes. The API Server validates them against its own public keys.
* **Webhook Token Authentication:** Delegates token verification to an external REST service.

#### 3. Authorization (AuthZ)
Once identity is confirmed, the request moves to authorization. All authorization modules are checked in order. If any module approves, the request proceeds. If all fail or none match, it returns a `403 Forbidden`.
* **RBAC (Role-Based Access Control):** Maps permissions (verbs: `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`) on resources to subjects (users, groups, service accounts) via `RoleBindings` and `ClusterRoleBindings`.
* **Node Authorization:** A specialized authorizer that limits a kubelet's permissions to only read/write resources associated with its specific node (e.g., Pods scheduled on it, ConfigMaps, Secrets mounted on those pods).
* **Webhook:** Delegated authorization to an external REST endpoint.

#### 4. Admission Control
Admission controllers are compiled-in plugins or external webhooks that intercept requests **only for mutating operations (create, update, delete)**. They do not run for read-only actions (`get`, `list`, `watch`).

Admission occurs in two distinct phases:
1. **Mutating Admission:** Mutates the request payload. For example, the `PodPreset` controller injects environment variables, or custom mutating webhooks inject sidecar containers (like Istio/Linkerd proxies). Mutating webhooks are run in alphabetical order.
2. **Object Schema Validation:** Verifies that the post-mutation object complies with the resource definition schemas.
3. **Validating Admission:** Evaluates the final object against compliance policies. Validating webhooks run in parallel. If any validator rejects the request, the API Server immediately returns a failure code. For example, OPA Gatekeeper or Kyverno blocking privileged containers.

---

## 💾 etcd: Distributed Consensus & Storage Internals

`etcd` is a strongly consistent, distributed key-value store. It is the single source of truth for Kubernetes.

### Raft Consensus Protocol
To ensure high availability and consistency, etcd clusters operate with an odd number of members (typically 3 or 5).
* **Quorum:** To commit a write, a leader must receive acknowledgement from a majority (quorum) of nodes:
  $$\text{Quorum} = \lfloor N/2 \rfloor + 1$$
  For a 3-node cluster, quorum is 2. For a 5-node cluster, quorum is 3.
* **Leader Election:** If the leader ceases sending heartbeats, followers enter candidate status and request votes. The candidate with the most up-to-date Write-Ahead Log (WAL) is elected leader.
* **WAL (Write-Ahead Log):** Every write is appended to a WAL on disk before it is committed to memory. This guarantees durability in the event of a sudden power loss.

### MVCC (Multi-Version Concurrency Control)
In etcd, keys are not updated in-place.
* **Revisions:** The database maintains a global 64-bit counter representing the cluster revision. Every write operation (put, delete) increments this revision counter.
* **Historical Versions:** A key `/keys/pods/default/nginx` might exist at revision 10 with value `v1`, and at revision 15 with value `v2`. Querying the key without specifying a revision returns the latest value. Querying with `revision=10` returns the historical state.
* **Watch API:** The Watch API utilizes this revision system. A client can request a watch from `Revision X`. The API server streams all events that happened from that exact point onwards, preventing any data loss during client reconnections.

### Memory & Disk Architecture
* **B-Tree Index:** Kept in-memory. Maps a key string (e.g., `/registry/pods/default/nginx`) to its database revisions.
* **BoltDB / bbolt:** An on-disk transactional key-value store. Keys in BoltDB are represented as `revision_number` and values are the serialized protobuf payloads of Kubernetes resources.
* **Compaction:** Since etcd never overwrites, it will grow indefinitely. Periodic compaction discards revisions older than a specific window (e.g., 5 minutes or a specific retention history).
* **Defragmentation:** Compaction leaves sparse holes in the BoltDB database file on disk. Defragmentation rewrites the database file sequentially to reclaim storage space.

---

## 🗓️ The Scheduler Workflow (`kube-scheduler`)

The Scheduler is a control plane client that maps unscheduled Pods (`spec.nodeName` is empty) to nodes.

```
Queue ➡️ Filter (Predicates) ➡️ Score (Priorities) ➡️ Select ➡️ Bind
```

### 1. Scheduling Queue
Pods awaiting scheduling are placed in an active queue. They are ordered based on priority class values.

### 2. Filtering Phase (Predicates)
Filters out nodes that cannot run the Pod. Predicates include:
* `NodeResourcesFit`: Verifies if the node has sufficient CPU and memory resources requested by the pod.
* `NodeName`: Matches the node name if a specific host was requested (`spec.nodeName`).
* `NodePorts`: Checks if the host ports requested by the pod are already occupied on the node.
* `PodTopologySpread`: Ensures pods are distributed across zones or regions.
* `NodeAffinity`: Assesses node selector labels and affinity rules.
* `TaintsAndTolerations`: Rejects nodes with taints that the pod does not tolerate.

### 3. Scoring Phase (Priorities)
For all nodes that passed the filtering phase, the scheduler calculates a score between 0 and 100 based on active priority functions:
* `ImageLocalityPriority`: Assigns higher scores to nodes that already have the container images cached, reducing pull latency.
* `NodeResourcesBalancedAllocation`: Evaluates resource utilization balance. It prefers nodes where the ratio of CPU to Memory usage after scheduling remains balanced.
* `NodeAffinityPriority`: Scores based on preferred (soft) node affinity rules.
* `SelectorSpreadPriority`: Attempts to spread pods belonging to the same Service or ReplicaSet across different nodes.

### 4. Binding Phase
The node with the highest score is chosen. If there is a tie, a node is chosen at random. The scheduler then writes a `Binding` object to the API Server, setting `spec.nodeName` to the target node. This is an atomic operation.

---

## 🔄 The Controller Manager Internals (`kube-controller-manager`)

The Controller Manager contains a collection of controllers that run reconciliation loops.

### Informer Architecture
To avoid overwhelming the API Server with poll requests, Kubernetes controllers use **Informers**:

```
[kube-apiserver] ➡️ (Watch Stream) ➡️ [Reflector] ➡️ [DeltaFIFO Queue] ➡️ [Indexer Cache (Local)]
                                                                    ➡️ [Resource Event Handlers] ➡️ [WorkQueue]
```

1. **Reflector:** Establishes a long-lived HTTP `Watch` connection to the API Server. It fetches the resource state and streams changes.
2. **DeltaFIFO Queue:** The Reflector pushes change events (Add, Update, Delete) into a first-in, first-out queue.
3. **Indexer (Local Cache):** The Informer pops events from DeltaFIFO, updates its local thread-safe in-memory cache, and index keys for efficient retrieval.
4. **Resource Event Handlers:** The Informer invokes user-defined callback handlers:
   * `OnAdd(obj)`
   * `OnUpdate(oldObj, newObj)`
   * `OnDelete(obj)`
5. **WorkQueue:** The event handlers compute the key of the changed resource (e.g., `default/nginx-deployment`) and push it onto a WorkQueue.
6. **Worker Loop:** Worker threads pull keys from the WorkQueue and call `Reconcile(key)`. The reconcile loop queries the Indexer local cache to check the actual state and calls the API Server to perform updates if there is a discrepancy.

---

## 🧬 The Node Agent: Kubelet Sync Loop

The `kubelet` is the node commander. It does not run as a container; it runs as a systemd service directly on the host OS.

### The Sync Loop (`syncLoop`)
The kubelet runs a main loop that receives configurations from:
* The API Server (for pods scheduled to this node name).
* A local host directory (for Static Pods).
* A URL endpoint.

For each pod event, it spawns or directs a "Pod Worker" to execute:
1. **Volume Attachment:** Calls CSI drivers to attach and mount directories on the host disk.
2. **Sandbox Creation:** Calls the CRI runtime via gRPC to create a pod sandbox. This configures the pause container, network namespaces, and cgroups.
3. **Network Configuration:** The CRI invokes the CNI plugin (e.g., Calico, Cilium) to attach a virtual ethernet pair (`veth`), allocate an IP address, and configure host routing.
4. **Container Launch:** Pulls application images, sets up container storage layers, and issues the CRI start container instruction.
5. **Probing:** Launches local liveness, readiness, and startup probe monitors.

---

## 🔌 kube-proxy: Service Routing Internals

`kube-proxy` is responsible for implementing the cluster-wide Virtual IP (ClusterIP) abstraction for Services.

### 1. IPTables Mode
In IPTables mode, `kube-proxy` watches the API Server for Service and EndpointSlice changes. For every service, it writes rules into the host kernel's `netfilter` table.
* **NAT Translation:** When a pod sends a packet to a Service ClusterIP, the host kernel intercept the packet, performs Destination NAT (DNAT) to rewrite the target IP to one of the healthy Pod IPs, and forwards the packet.
* **Performance degradation:** IPTables rules are evaluated sequentially. A cluster with 2,000 services and 10,000 pods creates tens of thousands of rules. Evaluated sequentially, this causes substantial packet processing latency.

### 2. IPVS Mode (IP Virtual Server)
IPVS is a Layer-4 load balancing engine built into the Linux kernel.
* **Hash Tables:** IPVS stores routing rules in efficient hash tables. Rule lookup is an $O(1)$ constant time operation, regardless of whether there are 10 or 10,000 services.
* **Load Balancing Algorithms:** Supports round-robin, least-connections, and destination-hashing.

### 3. eBPF Mode (e.g., Cilium)
Modern clusters run without `kube-proxy`. Instead, an eBPF program is attached directly to the network interface cards (TC hooks) or socket layers.
* **Bypassing Netfilter:** Packets bypass the entire netfilter stack in the kernel. The eBPF program translates the target destination IP directly at the socket level (`connect()` syscall), resulting in massive performance improvements and lower CPU consumption.
