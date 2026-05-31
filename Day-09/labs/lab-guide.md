# 🛠️ Day 09 Hands-On Lab Guide — Deploying Distributed Clusters

This lab guide walks you through deploying, verifying, and testing the resilience of PostgreSQL, Apache Kafka (KRaft), Elasticsearch, and Apache Pinot clusters on Kubernetes.

---

## 🎯 Lab Objectives
1. Deploy a StatefulSet configuration and observe the ordered startup sequence.
2. Verify stable DNS hostnames and network routing via Headless Services.
3. Test storage persistence during pod crashes.
4. Execute a rolling upgrade and observe the reverse ordinal rollout strategy.
5. Simulate a node partition/pod failure and verify recovery.

---

## ⚡ Prerequisites
* A running local Kubernetes cluster (Kind, Minikube, or custom cluster).
* The `kubectl` command line tool configured to access the cluster.
* All manifests generated in the [manifests/](../manifests/) directory.

---

## 🏁 Step 1: Deploy Headless Services

Headless Services must be applied first to allow database nodes to resolve each other's hostnames during boot.

```bash
kubectl apply -f manifests/01-headless-services.yaml
```

### Expected Output:
```text
service/postgres-headless created
service/kafka-headless created
service/elasticsearch-headless created
service/pinot-headless created
```

Verify that no cluster IPs are allocated:
```bash
kubectl get svc -o wide
```

### Expected Output:
```text
NAME                     TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                      AGE   SELECTOR
elasticsearch-headless   ClusterIP   None         <none>        9200/TCP,9300/TCP            10s   app=elasticsearch
kafka-headless           ClusterIP   None         <none>        9092/TCP,9093/TCP            10s   app=kafka
kubernetes               ClusterIP   10.96.0.1    <none>        443/TCP                      24d   <none>
pinot-headless           ClusterIP   None         <none>        8090/TCP,8098/TCP,8099/TCP   10s   app=pinot-server
postgres-headless        ClusterIP   None         <none>        5432/TCP                     10s   app=postgres
```
*Note that CLUSTER-IP is set to `None` for all database services.*

---

## 🏁 Step 2: Deploy & Observe PostgreSQL Ordered Startup

Apply the PostgreSQL configuration:
```bash
kubectl apply -f manifests/02-postgres.yaml
```

Now, quickly watch the pods being scheduled to observe the sequential creation:
```bash
kubectl get pods -w
```

### Expected Output:
```text
NAME         READY   STATUS              RESTARTS   AGE
postgres-0   0/1     ContainerCreating   0          2s
postgres-0   1/1     Running             0          12s
postgres-1   0/1     Pending             0          0s
postgres-1   0/1     ContainerCreating   0          1s
postgres-1   1/1     Running             0          10s
postgres-2   0/1     Pending             0          0s
postgres-2   0/1     ContainerCreating   0          1s
postgres-2   1/1     Running             0          11s
```
*Observe that `postgres-1` did not schedule until `postgres-0` transitioned to the `Ready` state (1/1).*

---

## 🏁 Step 3: Verify Storage Persistence and Identity

Let's verify that each PostgreSQL replica got its own individual disk volume:
```bash
kubectl get pvc
```

### Expected Output:
```text
NAME                          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pg-storage-postgres-0         Bound    pvc-876a9b1c-9ef1-42e8-97c3-a3d5f8a0021c   5Gi        RWO            standard       1m
pg-storage-postgres-1         Bound    pvc-1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d   5Gi        RWO            standard       45s
pg-storage-postgres-2         Bound    pvc-9z8y7x6w-5v4u-3t2s-1r0q-9p8o7n6m5l4k   5Gi        RWO            standard       30s
```

### Write Data to the Database:
Let's connect to `postgres-0` and insert a record:
```bash
kubectl exec -it postgres-0 -- psql -U k8s_admin -d production_db -c "CREATE TABLE test_table (id SERIAL PRIMARY KEY, data VARCHAR(50));"
kubectl exec -it postgres-0 -- psql -U k8s_admin -d production_db -c "INSERT INTO test_table (data) VALUES ('Kubernetes StatefulSet Validation');"
```

### Simulate Pod Crash:
Delete `postgres-0` to simulate a host failure:
```bash
kubectl delete pod postgres-0
```

Because it is a StatefulSet, the controller will immediately recreate `postgres-0`. Watch it boot and verify it mounts the same disk:
```bash
kubectl get pod postgres-0 -w
```

Once it returns to running status, check if the data survived:
```bash
kubectl exec -it postgres-0 -- psql -U k8s_admin -d production_db -c "SELECT * FROM test_table;"
```

### Expected Output:
```text
 id |                data                 
----+-------------------------------------
  1 | Kubernetes StatefulSet Validation
(1 row)
```
*The data survived because `postgres-0` reattached to the existing PVC `pg-storage-postgres-0`.*

---

## 🏁 Step 4: Deploy & Verify Apache Kafka (KRaft Mode)

Apply the multi-broker Kafka StatefulSet manifest:
```bash
kubectl apply -f manifests/03-kafka.yaml
```

Verify that all three brokers boot and form a quorum. Inspect the logs of `kafka-0` to see it identify as broker ID 0 and voter:
```bash
kubectl logs kafka-0 | grep -i "Raft"
```

### Verify Hostname Resolution:
Exec into `kafka-0` and run DNS query to verify headless network resolution:
```bash
kubectl exec -it kafka-0 -- nslookup kafka-1.kafka-headless.default.svc.cluster.local
```

### Expected Output:
```text
Server:		10.96.0.10
Address:	10.96.0.10#53

Name:	kafka-1.kafka-headless.default.svc.cluster.local
Address: 10.244.1.89
```

---

## 🏁 Step 5: Deploy & Configure Elasticsearch (Master Discovery)

Apply the Elasticsearch configuration:
```bash
kubectl apply -f manifests/04-elasticsearch.yaml
```

*Note: Since the manifest contains an init container adjusting kernel settings, the pod may take up to 30-45 seconds to initialize.*

Verify cluster health and node discovery:
```bash
kubectl exec -it elasticsearch-0 -- curl -s http://localhost:9200/_cluster/health?pretty
```

### Expected Output:
```json
{
  "cluster_name" : "k8s-elk-cluster",
  "status" : "green",
  "timed_out" : false,
  "number_of_nodes" : 3,
  "number_of_data_nodes" : 3,
  "active_primary_shards" : 0,
  "active_shards" : 0,
  "relocating_shards" : 0,
  "initializing_shards" : 0,
  "unassigned_shards" : 0
}
```
*Confirm that `number_of_nodes` shows 3, indicating the Zen discovery mechanism resolved the headless DNS entries and successfully formed a cluster.*

---

## 🏁 Step 6: Deploy Apache Pinot Complete Stack

Apply the Pinot stack including ZooKeeper, Controller, Broker, and Servers:
```bash
kubectl apply -f manifests/05-pinot.yaml
```

Verify that all Pinot sub-components are running:
```bash
kubectl get pods -l course=30-days-of-k8s
```

### Expected Output:
```text
NAME                                READY   STATUS    RESTARTS   AGE
pinot-broker-7bc9f874d-w92k8        1/1     Running   0          2m
pinot-controller-0                  1/1     Running   0          2m
pinot-server-0                      1/1     Running   0          1m
pinot-server-1                      1/1     Running   0          1m
pinot-zookeeper-6bfdfb867c-9b7d2    1/1     Running   0          2m
```

The Pinot Controller acts as the admin center. Verify you can access its rest interface:
```bash
kubectl exec -it pinot-controller-0 -- curl -s http://localhost:9000/health
```

---

## 🏁 Step 7: Test Rolling Upgrades in Reverse Ordinal Sequence

Let's update the PostgreSQL image version from `15.5-alpine` to `15.6-alpine` and observe the rollout sequence:
```bash
kubectl set image sts/postgres postgres=postgres:15.6-alpine
```

Now, monitor the update sequence:
```bash
kubectl get pods -w
```

### Expected Output:
```text
postgres-2   1/1     Terminating   0          5m
postgres-2   0/1     Terminating   0          5m
postgres-2   0/1     Pending       0          0s
postgres-2   0/1     ContainerCreating   0          1s
postgres-2   1/1     Running       0          12s
postgres-1   1/1     Terminating   0          5m
postgres-1   0/1     Terminating   0          5m
...
```
*Observe that `postgres-2` (the highest ordinal index) is terminated first. Only after `postgres-2` passes its readiness check does the controller terminate and update `postgres-1`. The database leader (`postgres-0`) is protected and updated last.*

---

## 🏁 Step 8: Clean Up

To avoid orphaned volume charges, delete the StatefulSets, then manually delete the PVCs:

```bash
kubectl delete -f manifests/
kubectl delete pvc --all
```
