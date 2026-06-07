# Lab 3: Spin up the EFK Logging Pipeline

In this lab, you will deploy Elasticsearch and Kibana to complete the EFK stack. You will configure Fluent Bit to write JSON logs to Elasticsearch index segments, configure Kibana indices, and inspect full-text search capabilities.

---

## Step 1: Deploy Elasticsearch Data Node

Apply the StatefulSet to provision the Elasticsearch storage backend:

```bash
kubectl apply -f ../manifests/elasticsearch-deployment.yaml
```

*Note on sysctl initContainer:* Elasticsearch requires elevated `vm.max_map_count` limits on the host node kernel. The manifest includes a privileged initContainer to set this value on startup.

Wait for Elasticsearch to initialize:
```bash
kubectl rollout status statefulset/elasticsearch -n logging
```

Verify the endpoint is reachable internally:
```bash
kubectl run es-test --image=curlimages/curl -n logging -i --tty --rm -- \
  curl http://elasticsearch.logging.svc.cluster.local:9200
```
*Expected Output:*
```json
{
  "name" : "elasticsearch-0",
  "cluster_name" : "docker-cluster",
  "version" : {
    "number" : "7.17.9"
  },
  "tagline" : "You Know, for Search"
}
```

---

## Step 2: Deploy Kibana Interface Portal

Deploy Kibana UI and link it to our Elasticsearch data service:

```bash
kubectl apply -f ../manifests/kibana-deployment.yaml
```

Verify Kibana is healthy:
```bash
kubectl rollout status deployment/kibana -n logging
```

---

## Step 3: Enable Elasticsearch Output on Fluent Bit

By default, the Fluent Bit configmap we applied in Lab 1 is configured to route logs to both Loki and Elasticsearch outputs. 

Let's check the pods and make sure Fluent Bit is successfully connecting to the Elasticsearch port:
```bash
# Get logs from a Fluent Bit agent
kubectl logs -n logging daemonset/fluent-bit -c fluent-bit --tail=100
```
Search the log output for connection logs:
```text
[2026/06/07 12:05:00] [ info] [output:es:es.1] elasticsearch-0.logging.svc.cluster.local:9200 connection OK
```

---

## Step 4: Create Kibana Index Patterns

1. Port-forward the Kibana interface:
   ```bash
   kubectl port-forward svc/kibana -n logging 5601:5601
   ```

2. Open `http://localhost:5601` in your browser.
3. Open the left sidebar, scroll down to **Management ➔ Stack Management ➔ Kibana Index Patterns**.
4. Click **Create index pattern**.
5. Set **Index pattern name** to `k8s-logs-*` (matching Fluent Bit's output prefix). Click **Next step**.
6. Select `@timestamp` as the primary time field, and click **Create index pattern**.

---

## Step 5: Querying Logs using Kibana Discover

1. Go to the left sidebar and click **Analytics ➔ Discover**.
2. Select the `k8s-logs-*` index pattern.
3. Use the search bar to enter search strings.
   * **KQL query for errors:** `kubernetes.namespace_name : "demo-apps" AND level : "warn"`
   * **Structured property search:** `kubernetes.pod_name : "structured-json-logger-*"`
4. Click on any log entry row to expand the record details. Notice how Elasticsearch parsed the internal fields (e.g. `latency_ms`, `trace_id`) into distinct, queryable dictionary keys automatically.

---

## Step 6: Configure Index Lifecycle Policies (ILM)

In a production environment, Elasticsearch indexes grow indefinitely, leading to disk exhaustion. SREs use Index Lifecycle Management (ILM) policies to delete logs after their retention window.

Run the following API call in Kibana's **Dev Tools** console (`http://localhost:5601/app/dev_tools#/console`) to create a policy:

```json
PUT _ilm/policy/k8s_logs_retention_policy
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "50gb",
            "max_age": "7d"
          }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```
This policy ensures indices roll over dynamically when they reach 50GB or 7 days, and are automatically deleted after 30 days.
