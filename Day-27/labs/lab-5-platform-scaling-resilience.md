# Lab 5: Stateful Platform Scaling & Resilience Testing

## Objective
Simulate real-world data scaling, perform live failure recovery, monitor partition reassignment, and execute an online persistent volume size expansion.

---

## Step 1: Start Ingest Traffic
Run the Python Kafka producer script to stream clickstream events to the Kafka cluster:

1. Copy the producer script to a temporary pod or run it locally if Python is installed. To execute inside the cluster, run:
   ```bash
   kubectl run python-producer --image=python:3.9-slim --restart=Never --overrides='
   {
     "spec": {
       "containers": [
         {
           "name": "producer",
           "image": "python:3.9-slim",
           "command": ["sh", "-c", "pip install kafka-python && python -u /tmp/producer.py"],
           "volumeMounts": [
             {
               "name": "script-vol",
               "mountPath": "/tmp"
             }
          ]
         }
       ],
       "volumes": [
         {
           "name": "script-vol",
           "configMap": {
             "name": "producer-script-cm"
           }
         }
       ]
     }
   }'
   ```
   *(Note: You can create a ConfigMap containing `producer.py` first, or run `python producer.py` locally and point it to a port-forwarded bootstrap broker: `kubectl port-forward svc/production-kafka-kafka-bootstrap 9092:9092`)*

---

## Step 2: Validate Pinot Real-Time Ingestion
Go to the Pinot Query Console (`http://localhost:9000/#/query`) and execute the following SQL:
```sql
SELECT platform, count(*), sum(revenue_usd) FROM userClicks GROUP BY platform
```
Run this query multiple times. You should see the count values increasing in real-time as the Python producer publishes records.

---

## Step 3: Scale Pinot Servers
As segment count grows, Pinot Server memory and disk usage will increase. We will scale the Pinot Server StatefulSet from 2 to 3 replicas.

1. Trigger the scale:
   ```bash
   kubectl scale statefulset pinot-server --replicas=3
   ```
2. Watch the scheduling:
   ```bash
   kubectl get pods -w -l app=pinot-server
   ```
   *Note: Because we use `volumeBindingMode: WaitForFirstConsumer` on the storage class, the PVC for `pinot-server-2` remains `Pending` until the scheduler assigns the pod to a node. Once the node selection completes, the volume is provisioned in the matching availability zone, and the pod starts.*

Verify ZooKeeper registers the new server instance:
```bash
kubectl exec -it deployment/pinot-controller -- bin/pinot-admin.sh ShowClusterInfo -zkAddress production-kafka-zookeeper-client:2181
```

---

## Step 4: Simulate Kafka Broker Failure & Recovery
Kafka is designed to be resilient to broker failures. We will terminate the partition leader broker and verify partition failover.

1. Find the partition leaders for `user-clicks` topic:
   ```bash
   kubectl exec -it production-kafka-kafka-0 -- bin/kafka-topics.sh \
     --bootstrap-server localhost:9092 --describe --topic user-clicks
   ```
   *Expected Output:*
   ```
   Topic: user-clicks  Partition: 0  Leader: 1  Replicas: 1,2,0  Isr: 1,2,0
   Topic: user-clicks  Partition: 1  Leader: 2  Replicas: 2,0,1  Isr: 2,0,1
   ```
2. Delete the pod for Broker 1:
   ```bash
   kubectl delete pod production-kafka-kafka-1
   ```
3. Immediately run the describe command again to watch the leader election:
   ```bash
   kubectl exec -it production-kafka-kafka-0 -- bin/kafka-topics.sh \
     --bootstrap-server localhost:9092 --describe --topic user-clicks
   ```
   *Expected Output:*
   ```
   Topic: user-clicks  Partition: 0  Leader: 2  Replicas: 1,2,0  Isr: 2,0
   ```
   Notice that Partition 0 leader failed over to Broker 2. The In-Sync Replica (ISR) list drops Broker 1 (`Isr: 2,0`).
4. Watch the StatefulSet recreate the pod. Once `production-kafka-kafka-1` is healthy, it will sync state and join the ISR:
   ```
   Topic: user-clicks  Partition: 0  Leader: 2  Replicas: 1,2,0  Isr: 2,0,1
   ```

---

## Step 5: Execute Online PVC Volume Expansion
Our Kafka cluster's persistent storage is filling up. We need to expand the volume size dynamically without taking the cluster offline.

1. Verify that the storage class supports expansion (`allowVolumeExpansion: true`):
   ```bash
   kubectl get storageclass local-nvme
   ```
2. Edit the PVC for Broker 0:
   ```bash
   kubectl edit pvc data-production-kafka-kafka-0
   ```
3. Locate the `resources.requests.storage` line and increase it from `100Gi` to `150Gi`. Save and exit.
4. Verify the volume expansion status:
   ```bash
   kubectl describe pvc data-production-kafka-kafka-0
   ```
   Look for events showing `FileSystemResizeSuccessful`.
5. Run the disk command inside the pod to verify:
   ```bash
   kubectl exec -it production-kafka-kafka-0 -- df -h /var/lib/kafka/data
   ```
   You will see the partition size updated to `150G` without restarting the Kafka process!
