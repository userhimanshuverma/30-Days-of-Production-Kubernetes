# Lab 4: Deploying Apache Pinot (OLAP) on Kubernetes

## Objective
Deploy Apache Pinot (Controller, Broker, Server, and Minion pods), link them to the ZooKeeper consensus cluster, create the `userClicks` schema, and deploy the table config for real-time Kafka ingestion.

---

## Step 1: Deploy Apache Pinot
We will deploy Pinot using our manifest file. The Pinot components are configured to connect to ZooKeeper (`production-kafka-zookeeper-client:2181`) for cluster metadata and routing.

Apply the Pinot manifest:
```bash
kubectl apply -f manifests/pinot-cluster.yaml
```
*Expected Output:*
```
service/pinot-controller created
deployment.apps/pinot-controller created
service/pinot-broker created
deployment.apps/pinot-broker created
service/pinot-server created
statefulset.apps/pinot-server created
deployment.apps/pinot-minion created
```

Monitor pod readiness:
```bash
kubectl get pods -l 'app in (pinot-controller, pinot-broker, pinot-server, pinot-minion)'
```
Wait until all pods are running and ready. The Pinot Server StatefulSet will initialize two server replicas (`pinot-server-0`, `pinot-server-1`).

---

## Step 2: Access the Pinot Controller Console
The Controller hosts a web dashboard to manage tables, schemas, and queries.

1. Port-forward the Controller service port:
   ```bash
   kubectl port-forward svc/pinot-controller 9000:9000
   ```
2. Open your browser and navigate to `http://localhost:9000`. You will see the Apache Pinot Query Console and Cluster Manager interface.

---

## Step 3: Define Schema and Table Configurations
Pinot requires schemas to process incoming data. We will define a real-time table that reads JSON objects directly from the Kafka `user-clicks` topic.

1. Submit the schema config:
   ```bash
   kubectl exec -i deployment/pinot-controller -- bin/pinot-admin.sh AddSchema \
     -schemaFilePath /opt/pinot/user-clicks-schema.json -exec
   ```
   *Note: Since we are running local commands, copy the schema configuration first, or pipe the JSON file directly:*
   ```bash
   kubectl exec -i deployment/pinot-controller -- tee /tmp/schema.json < pinot/user-clicks-schema.json
   
   kubectl exec -i deployment/pinot-controller -- bin/pinot-admin.sh AddSchema \
     -schemaFilePath /tmp/schema.json -exec
   ```
   *Expected Output:*
   ```
   Status: 200 OK
   Schema userClicks added successfully.
   ```

2. Submit the table configuration:
   ```bash
   kubectl exec -i deployment/pinot-controller -- tee /tmp/table-config.json < pinot/user-clicks-table-config.json
   
   kubectl exec -i deployment/pinot-controller -- bin/pinot-admin.sh AddTable \
     -tableConfigFile /tmp/table-config.json -exec
   ```
   *Expected Output:*
   ```
   Status: 200 OK
   Table userClicks_REALTIME added successfully.
   ```

---

## Step 4: Verify Real-Time Table Registration
In the Pinot Console (`http://localhost:9000`), click on the **Tables** tab. You should see `userClicks` listed as a `REALTIME` table. 

Click on the table name. You will see that the table is actively subscribing to the Kafka topic. Pinot is now ready to receive data from our streaming producer.
