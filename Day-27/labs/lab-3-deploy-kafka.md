# Lab 3: Deploying Apache Kafka (Strimzi Operator) on Kubernetes

## Objective
Install the Strimzi Kafka Operator, deploy a highly available, multi-broker Kafka cluster with persistent ZooKeeper metadata nodes, and verify broker routing.

---

## Step 1: Install Strimzi Kafka Operator
The Strimzi Operator manages the deployment of Kafka brokers, ZooKeeper quorum nodes, Kafka topics, and connection details.

1. Add the Strimzi Helm repository:
   ```bash
   helm repo add strimzi https://strimzi.io/charts/
   helm repo update
   ```
2. Install the operator:
   ```bash
   helm install strimzi-operator strimzi/strimzi-kafka-operator --namespace default
   ```
3. Verify the operator pod is running:
   ```bash
   kubectl get pods -l name=strimzi-cluster-operator
   ```

---

## Step 2: Deploy the 3-Broker Kafka Cluster
We will deploy a 3-node Kafka cluster and a 3-node ZooKeeper cluster. Each broker pod requires a PersistentVolumeClaim to store topic commit logs. The broker pods use pod anti-affinity rules to ensure they are scheduled on separate physical worker nodes.

Apply the Kafka cluster manifest:
```bash
kubectl apply -f manifests/kafka-strimzi-cluster.yaml
```
Monitor the rollout of ZooKeeper followed by Kafka:
```bash
kubectl get pods -w
```
*Expected Rollout Sequence:*
1. **ZooKeeper Quorum**: `production-kafka-zookeeper-0`, `production-kafka-zookeeper-1`, `production-kafka-zookeeper-2` are spun up.
2. **Kafka Brokers**: `production-kafka-kafka-0`, `production-kafka-kafka-1`, `production-kafka-kafka-2` are initialized sequentially.
3. **Operators**: Entity Operator pod starts to manage topics and users.

Wait until all pods are `Running` and `READY`:
```
NAME                                          READY   STATUS    RESTARTS   AGE
production-kafka-zookeeper-0                  1/1     Running   0          2m
production-kafka-zookeeper-1                  1/1     Running   0          95s
production-kafka-zookeeper-2                  1/1     Running   0          60s
production-kafka-kafka-0                      1/1     Running   0          45s
production-kafka-kafka-1                      1/1     Running   0          30s
production-kafka-kafka-2                      1/1     Running   0          15s
production-kafka-entity-operator-7b5f-abcde   3/3     Running   0          10s
```

---

## Step 3: Create a Kafka Topic
Create a Kafka Topic named `user-clicks` with 6 partitions and a replication factor of 3.

Apply the KafkaTopic manifest:
```bash
kubectl apply -f manifests/kafka-topic.yaml
```
Verify the topic creation:
```bash
kubectl get kafkatopics
```
*Expected Output:*
```
NAME          CLUSTER            PARTITIONS   REPLICAS   READY
user-clicks   production-kafka   6            3          True
```

---

## Step 4: Verify Streaming Communication
To verify the Kafka cluster, launch an interactive pod inside the namespace to act as a test client:

1. Spawn a test client pod:
   ```bash
   kubectl run kafka-consumer -it --image=strimzi/kafka:0.26.0-kafka-3.0.0 --restart=Never -- \
     bin/kafka-console-consumer.sh --bootstrap-server production-kafka-kafka-bootstrap:9092 --topic user-clicks --from-beginning
   ```
2. In a separate terminal window, produce some messages:
   ```bash
   kubectl run kafka-producer -it --image=strimzi/kafka:0.26.0-kafka-3.0.0 --restart=Never -- \
     bin/kafka-console-producer.sh --bootstrap-server production-kafka-kafka-bootstrap:9092 --topic user-clicks
   ```
   Type a few lines of messages in the producer prompt and watch them appear in the consumer window:
   ```
   >hello world
   >testing production kafka
   ```

To clean up the test client pods:
```bash
kubectl delete pod kafka-producer kafka-consumer
```
