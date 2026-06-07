# Lab 2: Deploy Loki & Query Logs using Grafana LogQL

In this lab, you will deploy Grafana Loki to act as a lightweight, label-indexed log aggregation database. You will run a traffic demo-app and query logs using Grafana dashboards and LogQL.

---

## Step 1: Deploy Loki Single-Replica Database

We will deploy Loki to our `logging` namespace:

```bash
kubectl apply -f ../manifests/loki-single-binary.yaml
```

Verify that the StatefulSet starts and the volume mount claim is bound:
```bash
kubectl get statefulset loki -n logging
kubectl get pvc -n logging
```

---

## Step 2: Spin Up Grafana Dashboard

To keep our cluster lightweight, we will run a standard standalone Grafana instance:

```bash
kubectl create deployment grafana --image=grafana/grafana:10.2.0 -n logging
kubectl expose deployment grafana --port=3000 --target-port=3000 -n logging
```

Wait for Grafana to start:
```bash
kubectl rollout status deployment/grafana -n logging
```

---

## Step 3: Access Grafana and Add Loki Datasource

1. Port-forward the Grafana service:
   ```bash
   kubectl port-forward svc/grafana -n logging 3000:3000
   ```

2. Open your web browser and go to `http://localhost:3000`.
   * **Login credentials:** `admin` / `admin` (skip password reset).

3. Add Loki as a Datasource:
   * Navigate to **Connections ➔ Data Sources ➔ Add data source**.
   * Select **Loki**.
   * Set the URL to: `http://loki.logging.svc.cluster.local:3100`.
   * Scroll to the bottom and click **Save & test**. You should see a green success message: *“Data source successfully connected”*.

---

## Step 4: Run Sample Traffic Applications

We will deploy our sample structured and unstructured log generators to a dedicated namespace:

```bash
kubectl apply -f ../manifests/sample-logging-apps.yaml
```

Check that the generator pods are active and writing logs:
```bash
kubectl get pods -n demo-apps
```

---

## Step 5: Write LogQL Queries in Grafana Explore

Navigate to the **Explore** tab in Grafana (compass icon on the sidebar) and select the **Loki** datasource.

### Query 1: Basic Stream Selection
Select logs from the structured logger container:
```logql
{namespace="demo-apps", app="structured-logger"}
```
Click **Run Query** in the upper right. You will see JSON logs streaming in.

### Query 2: Log Filtering (Regex Search)
Filter the log lines to show only messages containing checkout operations:
```logql
{namespace="demo-apps", app="structured-logger"} |= "checkout"
```

### Query 3: JSON Field Extraction
Since the application writes logs in JSON format, we can instruct Loki to parse fields dynamically at query time using the `json` pipe:
```logql
{namespace="demo-apps", app="structured-logger"} | json | latency_ms > 150
```
This extracts fields like `latency_ms` and allows numeric operations (e.g. finding high latency logs) without indexing the full text of the log.

### Query 4: Metric Queries (Error Rates)
Calculate the number of warnings/errors per minute over a 5-minute range:
```logql
sum by(level) (rate({namespace="demo-apps", app="structured-logger"} | json | level != "info" [5m]))
```
This query dynamically converts log streams into a metric graph on your dashboard.
