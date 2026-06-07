# Day 16 Exercises and Challenges

These exercises will test your hands-on knowledge of Fluent Bit filter configurations, Grafana Loki LogQL writing, and Elasticsearch storage optimization.

---

## Challenge 1: Configure Fluent Bit to Mask Credit Card Numbers

### Objective
Configure Fluent Bit to detect credit card patterns (e.g. `XXXX-XXXX-XXXX-XXXX` or 16-digit blocks) in application logs and replace them with `[REDACTED_PII]` before sending them to Loki/Elasticsearch.

### Steps
1. Open the [fluent-bit-configmap.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-16/manifests/fluent-bit-configmap.yaml).
2. Add a `[FILTER]` of type `modify` using the rules described in [lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-16/production-notes/lessons-learned.md).
3. Test your changes by deploying the config map, restarting the Fluent Bit DaemonSet, and verifying that the `credit_card` logs in the sample Python application appear as `[REDACTED_PII]` in your dashboards.

---

## Challenge 2: Write a LogQL Query for Error Percentages

### Objective
Write a LogQL query that calculates the percentage of log lines that are `level="warn"` or `level="error"` compared to the total log lines for the `checkout-service` over a rolling 10-minute window.

### Requirements
* The query must dynamically parse the JSON payload using `| json`.
* The metric graph should output a ratio between 0 and 100.
* *Hint:* The formula is: `(Rate of errors) / (Rate of total logs) * 100`.

---

## Challenge 3: Configure an Elasticsearch Retention Policy

### Objective
Write a `curl` script that configures an Elasticsearch Index Lifecycle Policy (ILM) named `dev-retention` that:
1. Moves index logs from the **Hot** phase to the **Warm** phase after 2 days or 10GB.
2. Automatically **Deletes** the index after 7 days to preserve disk space in development.
3. Apply this policy to all indexes starting with the pattern `k8s-logs-*` by creating an Index Template.

### Expected Deliverable
A shell script containing the required `curl` API operations pointing to your local Elasticsearch service: `http://elasticsearch.logging.svc.cluster.local:9200`.
