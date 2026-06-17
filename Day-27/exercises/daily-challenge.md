# Daily Challenge: Build the Unified Real-Time Streaming Pipeline

## The Goal
Your challenge today is to build a complete, end-to-end telemetry analytics pipeline on your local Kubernetes cluster. The pipeline should ingest live event traffic, store it in an OLAP database for real-time querying, and run batch aggregates.

```
                  ┌───────────────┐
                  │ Event Gen     │
                  │ (producer.py) │
                  └───────┬───────┘
                          │ (TCP 9092)
                          ▼
                  ┌───────────────┐
                  │ Kafka Cluster │
                  │ (user-clicks) │
                  └───────┬───────┘
            ┌─────────────┴─────────────┐
            │ (Real-time stream)        │ (Batch ETL)
            ▼                           ▼
    ┌───────────────┐           ┌───────────────┐
    │ Apache Pinot  │           │ Apache Spark  │
    │ (userClicks)  │           │ (pyspark-job) │
    └───────┬───────┘           └───────┬───────┘
            │                           │ (Mount PVC)
            ▼                           ▼
    ┌───────────────┐           ┌───────────────┐
    │ Query BI      │           │ Parquet /     │
    │ (HTTP 8099)   │           │ Delta Lake    │
    └───────────────┘           └───────────────┘
```

---

## The Challenge Tasks

### Task 1: Debug the Broken Manifests
In the [exercises/challenge-manifests.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-27/exercises/challenge-manifests.yaml) file, we have packaged the deployment files for your cluster. However, we have introduced three critical, production-realistic bugs:
1. **AZ Scheduling / Volume Binding Mismatch**: The StorageClass is configured to bind volumes immediately, causing pods to fail scheduling due to cross-AZ requirements.
2. **RBAC Executor Failure**: The Airflow Scheduler deployment tries to use a non-existent ServiceAccount, preventing scheduler startup.
3. **Kafka Service Connection Mismatch**: Mismatched selector labels on the headless discovery service are blocking communications.

**Your Objective**: Inspect, debug, and apply the fixed manifests until all components are running healthy.

---

## Lab Verification & Submission
1. Apply your corrected manifests:
   ```bash
   kubectl apply -f exercises/challenge-manifests.yaml
   ```
2. Confirm all pods are running successfully:
   ```bash
   kubectl get pods -n analytics-challenge
   ```
3. Run the Kafka producer:
   ```bash
   kubectl exec -it telemetry-producer -n analytics-challenge -- python producer.py
   ```
4. Run a query on the Pinot Broker showing that it is actively ingesting the events:
   ```bash
   kubectl exec -it pinot-controller -n analytics-challenge -- \
     curl -s http://localhost:9000/sql \
     -H 'Content-Type: application/json' \
     -d '{"sql":"SELECT platform, count(*), sum(revenue_usd) FROM userClicks GROUP BY platform"}'
   ```
5. Capture a screenshot of the Pinot query response and export your final applied YAML config.
