# 🏆 Day 09 Daily Challenges — StatefulSet Optimization

Test your architecture-level understanding of StatefulSets and distributed databases by completing these three hands-on challenges.

---

## 🧩 Challenge 1: Resolve Broken Peer Discovery in Kafka

### Scenario
You deploy a new Kafka cluster, but the brokers fail to establish communication. The logs of `kafka-1` show:
`[2026-05-31 12:00:00,000] WARN [RaftManager id=1] Connection to node 0 (kafka-0.kafka-headless.default.svc.cluster.local/10.244.1.4) could not be established. Broker may not be available. (org.apache.kafka.clients.NetworkClient)`

You check `kubectl get svc` and see:
`kafka-headless   ClusterIP   None   <none>   9092/TCP,9093/TCP   10m`

### Your Task
1. Inspect the Headless Service selector configuration in `manifests/01-headless-services.yaml` and the labels of the StatefulSet in `manifests/03-kafka.yaml`.
2. Identify why DNS hostnames are not resolving properly (Hint: Check selector labels mismatch).
3. Correct the manifests, re-apply them, and verify that `nslookup kafka-0.kafka-headless` resolves to the correct pod IP.

---

## 🧩 Challenge 2: Safely Expand Stateful Database Storage

### Scenario
Your Elasticsearch cluster is running low on disk space. If you reach the 85% watermark, Elasticsearch will disable writing to new indices. You need to expand the storage of the running Elasticsearch nodes from `10Gi` to `20Gi` **without destroying the data or deleting the pods**.

### Your Task
1. Edit the active PVC claims directly in the cluster:
   ```bash
   kubectl edit pvc elastic-data-elasticsearch-0
   kubectl edit pvc elastic-data-elasticsearch-1
   kubectl edit pvc elastic-data-elasticsearch-2
   ```
2. Modify the `spec.resources.requests.storage` from `10Gi` to `20Gi`.
3. Check if the volumes expanded dynamically:
   ```bash
   kubectl get pvc
   ```
4. Verify that the files inside the containers recognize the new size:
   ```bash
   kubectl exec -it elasticsearch-0 -- df -h /usr/share/elasticsearch/data
   ```
5. Explain in a brief markdown summary: What happens if your `StorageClass` has `allowVolumeExpansion: false`? How would you expand storage in that scenario?

---

## 🧩 Challenge 3: Configure a Pod Disruption Budget (PDB)

### Scenario
An automated maintenance script is draining cluster worker nodes to apply OS updates. You need to ensure that the 3-node PostgreSQL StatefulSet remains available during the drain. At least **2 database replicas must always be online** to maintain read/write quorum.

### Your Task
1. Write a new Kubernetes manifest named `manifests/06-postgres-pdb.yaml`.
2. Define a `PodDisruptionBudget` API object targeting the PostgreSQL StatefulSet.
3. Configure it to enforce a `minAvailable: 2` constraint.
4. Apply the PDB:
   ```bash
   kubectl apply -f manifests/06-postgres-pdb.yaml
   ```
5. Test the PDB by draining the node running `postgres-1` and checking if Kubernetes blocks draining the node running `postgres-2` until `postgres-1` completes rescheduling and passes its readiness probe:
   ```bash
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```
