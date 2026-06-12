# 🧠 etcd Architecture & Database Internals

**etcd** is a strongly consistent, distributed key-value store that acts as the single source of truth for Kubernetes. Every Kubernetes resource—from Pods and Secrets to Custom Resources (CRDs)—is stored inside etcd. If etcd is slow, your control plane lags; if etcd is corrupt, the cluster is dead.

---

## 1. The Raft Consensus Algorithm

To maintain consistency across multiple nodes, etcd uses **Raft**. Raft ensures that a cluster of nodes can agree on the database state even if some nodes fail.

### Quorum Math
To write data or elect a leader, etcd requires a **quorum** (majority) of active nodes. The quorum formula is:

$$\text{Quorum} = \left\lfloor \frac{N}{2} \right\rfloor + 1$$

Where $N$ is the total number of nodes in the cluster.

| Cluster Size ($N$) | Quorum Required | Tolerable Failures |
|---|---|---|
| 1 | 1 | 0 |
| 2 | 2 | 0 |
| **3** | **2** | **1** |
| 4 | 3 | 1 |
| **5** | **3** | **2** |

### Why Odd Node Counts are Mandatory
An odd number of nodes provides the best balance of failure tolerance and resource efficiency.
* **The Split-Brain Scenario**: Suppose you have a 4-node cluster. A network partition splits the cluster into two halves of 2 nodes each ($2+2$). Neither side can achieve quorum (which requires 3 nodes). The entire cluster becomes read-only and halts writes.
* **Resource Optimization**: A 4-node cluster requires 3 nodes for quorum and tolerates 1 failure. A 3-node cluster requires 2 nodes for quorum and also tolerates 1 failure. Thus, adding the 4th node adds cost and network overhead without increasing failure tolerance.

---

## 2. Multi-Version Concurrency Control (MVCC)

etcd does not update keys in-place. Instead, it uses **MVCC**, meaning every modification creates a new version of the key. This provides several benefits:
- **Historical Queries**: You can query the state of a key at a specific revision in the past.
- **Lock-Free Reads**: Readers do not block writers, and writers do not block readers.

### Key Terms:
* **Revision**: A 64-bit counter that acts as a global logical clock for the entire cluster. Every write operation (put or delete) increments the revision.
* **Version**: A counter representing the modifications of a specific key. It is reset to 0 when the key is deleted.

### Database Layout:
Internally, etcd maintains two indices:
1. **In-Memory B-Tree Index (keyIndex)**: Maps user keys (e.g. `/registry/pods/default/nginx`) to a struct containing all historical revisions.
2. **BoltDB B+ Tree Database (Disk-backed)**: Maps revisions (64-bit integers) to the actual key-value payload. BoltDB is a single memory-mapped database file (`member/snap/db`).

```
USER KEY                 IN-MEMORY INDEX                 DISK (BoltDB B+ Tree)
"foo"  ----------> [ Revision 3, Revision 5 ] ---> Rev 3 => { value: "bar", version: 1 }
                                              ---> Rev 5 => { value: "baz", version: 2 }
```

---

## 3. The Write Path (How a write is committed)

1. **Client Request**: A client (e.g., `kube-apiserver`) sends a `PUT /registry/secrets/production/api-key` request to the etcd leader.
2. **Proposal**: The leader proposes the write to the Raft consensus group.
3. **Write-Ahead Logging (WAL)**: The leader and followers write the proposal to their local WAL on disk. This is a sequential append-only operation, which is very fast.
4. **Replication & Quorum**: The leader waits for a majority of followers to confirm they have written the WAL.
5. **Commit**: Once quorum is reached, the leader commits the transaction and applies the write to BoltDB.
6. **Apply**: The leader returns success to the client.

---

## 4. Compaction & Defragmentation (SRE Database Maintenance)

Because of MVCC, etcd keeps all historical revisions of deleted and updated keys. Over time, the BoltDB file size will grow continuously until it hits the **quota limit** (default: 2GB, maximum: 8GB), causing the cluster to throw `mvcc: database space exceeded` errors.

To prevent this, SREs must manage compaction and defragmentation:

### Compaction
Compaction discards old historical revisions of keys up to a specific revision. For example, if you compact to revision 100, you can no longer query history before revision 100.
* **Auto-compaction**: Kubernetes configures etcd to auto-compact history. By default, it runs every 5 minutes or based on retention time.
* **Manual Compaction**:
  ```bash
  etcdctl compact 4820194
  ```

### Defragmentation
Compaction frees up space inside BoltDB, but it **does not** release the space back to the operating system filesystem. The database file remains the same size, containing "empty pages" (fragmentation).
To shrink the physical file size on disk, you must run defragmentation.
* **Command**:
  ```bash
  etcdctl defrag --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
  ```
* **IMPORTANT**: Defragmentation locks the database and blocks writes. In production, always run it sequentially, one node at a time (rolling defrag), to maintain cluster availability.
