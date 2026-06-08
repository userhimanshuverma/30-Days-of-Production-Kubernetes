# 🚨 Day 17 Troubleshooting & Diagnostics Playbook

This playbook provides actionable incident response guidelines, diagnostics commands, and resolution workflows for observability platform failures.

---

## Scenario 1: Scrape Target Offline (Missing Metrics)

### Symptoms
*   Grafana charts show `No Data` or gaps in line graphs.
*   Prometheus Web UI indicates targets in `DOWN` status under `Status -> Targets`.
*   An alert like `TargetScrapeFailed` or `NodeExporterOffline` fires.

### Root Cause
1.  **Network Isolation:** `NetworkPolicy` restricts traffic between the Prometheus scraper pod and the application metrics port.
2.  **Port Mismatch:** The Prometheus scrape configuration points to the wrong container port or endpoint path (e.g., `/metrics` instead of `/actuator/prometheus`).
3.  **RBAC Authorization Denied:** Prometheus's ServiceAccount lacks permissions to query endpoints or nodes.

### Investigation
1.  **Check Target Status in Prometheus Web UI:**
    Open the Prometheus UI, navigate to `Status -> Targets`, and inspect the `Error` column for the failing scrape target.
2.  **Verify Pod IP and Port Connectivity:**
    Find the target pod IP and run a test request from within a temporary shell running inside the `monitoring` namespace:
    ```bash
    kubectl run tmp-curl-pod --rm -i --tty --image=curlimages/curl --namespace=monitoring -- \
      curl -s http://<target-pod-ip>:<metrics-port>/metrics
    ```
    *   *If connection times out:* NetworkPolicy blocking exists.
    *   *If HTTP 404/403:* Port or path config typo.
3.  **Verify Endpoints Object exists:**
    ```bash
    kubectl get endpoints <service-name> -n <namespace>
    ```
    Ensure there are active IPs bound under the Service endpoint. If the endpoints array is empty, the pods are failing their readiness probes.

### Resolution
1.  **Correct Scrape Port/Annotations:**
    Update the pod's template annotations in the Deployment YAML to specify the correct port:
    ```yaml
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "9898"
      prometheus.io/path: "/metrics"
    ```
2.  **Open Network Access:**
    Configure a NetworkPolicy in the application namespace allowing ingress traffic from the `monitoring` namespace:
    ```yaml
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: allow-prometheus-scraping
      namespace: default
    spec:
      podSelector:
        matchLabels:
          app: customer-api
      ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                  kubernetes.io/metadata.name: monitoring
          ports:
            - protocol: TCP
              port: 9898
    ```

### Prevention
*   Enforce standard annotations for all applications.
*   Validate endpoints connectivity in CI/CD pipeline automation before promoting services.

---

## Scenario 2: Prometheus Out Of Memory (OOMKilled)

### Symptoms
*   The Prometheus Pod goes into `CrashLoopBackOff`.
*   Running `kubectl describe pod prometheus -n monitoring` shows the termination reason: `OOMKilled` (Exit Code 137).
*   Metrics collection gaps occur globally across all targets.

### Root Cause
A microservice began exporting a high-cardinality metric (e.g. including dynamic parameters like UUIDs, timestamps, or full SQL queries in the labels), causing the Prometheus index to balloon and exceed configured container memory limits.

### Investigation
1.  **Examine the WAL Tool (Offline Analysis):**
    If Prometheus cannot start, run the Prometheus TSDB tool against the persistent volume data directory to identify the highest cardinality metrics:
    ```bash
    # Run from a temporary container mounting the Prometheus volume
    ./prometheus tsdb analyze /prometheus
    ```
2.  **Verify Active Series Count in Prometheus logs (if running):**
    ```bash
    kubectl logs prometheus-0 -n monitoring -c prometheus --tail=500
    ```
    Search for log entries containing `head series` or `compaction`.
3.  **Query Active Series via PromQL (prior to crash):**
    If Prometheus starts briefly, run this instant query to locate the offending metric:
    ```promql
    topk(10, count by (__name__) ({__name__=~".+"}))
    ```

### Resolution
1.  **Increase Memory Allocation Temporarily:**
    Increase the Prometheus resource limits in the StatefulSet YAML (e.g., doubling memory request/limits) to allow Prometheus to start and parse the WAL.
2.  **Inject Relabel Drop Rules:**
    Identify the high-cardinality metric name (e.g., `http_request_client_ip_total`). Add a metric relabel rule to drop this metric before ingestion:
    ```yaml
    metric_relabel_configs:
      - source_labels: [__name__]
        regex: "http_request_client_ip_total"
        action: drop
    ```
3.  **Hot Reload Configuration:**
    Trigger a configuration reload without restarting the pod:
    ```bash
    kubectl exec -it prometheus-0 -n monitoring -- curl -X POST http://localhost:9090/-/reload
    ```

### Prevention
*   Enforce a `sample_limit` configuration rule in `prometheus.yml` scrape jobs to drop targets exceeding metrics ceilings (e.g. `sample_limit: 100000`).
*   Incorporate automated metric compliance checks in dev environments using tools like `promtool check metrics`.

---

## Scenario 3: Alert Storm / Double Paging

### Symptoms
*   On-call engineers receive dozens of PagerDuty alarms or Slack alerts within seconds.
*   Alerts are duplicate or relate to the same system fault (e.g. receiving a page for every pod failing, and another page saying the worker node went down).
*   Critical notification channels are flooded.

### Root Cause
1.  **Lack of Grouping Rules:** Alertmanager is configured with a short `group_wait` and does not group alerts by cluster/namespace, resulting in separate notifications for each failing target.
2.  **Missing Inhibition Rules:** When a physical node goes offline, the Node Exporter goes down *and* all container pods crash. Since no inhibition rule exists, Alertmanager triggers alerts for both issues instead of suppressing pod alerts.

### Investigation
1.  **Inspect Alertmanager Routing Configuration:**
    Check the `alertmanager.yml` routing block:
    ```bash
    kubectl get configmap alertmanager-config -n monitoring -o jsonpath='{.data.alertmanager\.yml}'
    ```
    Ensure `group_by` and `inhibit_rules` configurations are declared.
2.  **View Alertmanager Active Alerts UI:**
    Port-forward to Alertmanager (`kubectl port-forward svc/alertmanager 9093:9093 -n monitoring`) and inspect active alerts grouping.

### Resolution
1.  **Add Grouping Parameters:**
    Edit the Alertmanager config to ensure alerts are grouped by alertname and namespace:
    ```yaml
    route:
      group_by: ['alertname', 'kubernetes_namespace', 'service']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
    ```
2.  **Write Inhibition Rules:**
    Configure a rule specifying that if a node goes down (`NodeExporterOffline`), do not trigger pod CPU throttling warnings (`ContainerCpuThrottling`) on that same node:
    ```yaml
    inhibit_rules:
      - source_match:
          alertname: 'NodeExporterOffline'
        target_match:
          alertname: 'ContainerCpuThrottling'
        equal: ['node', 'instance']
    ```

### Prevention
*   Periodically review alerting routing trees.
*   Enforce a strict policy: "Alert on symptoms, not causes."

---

## Scenario 4: Sluggish Grafana Dashboard Queries

### Symptoms
*   Grafana panels spin for 10-30 seconds or return `Gateway Timeout (504)`.
*   Dashboard variables drop-downs load slowly or freeze the browser tab.

### Root Cause
1.  **Inefficient PromQL Queries:** Dashboard queries search using wildcards or unindexed regex patterns (e.g., `{pod=~".*api.*"}`).
2.  **High range queries without downsampling:** Users load 30-day graphs querying raw 15-second data points.
3.  **Variable Query Spikes:** Dynamic variables query the API to return thousands of distinct user names.

### Investigation
1.  **Use Grafana Query Inspector:**
    Open a slow panel, click `Inspect -> Query`, and check the execution time. Look at the raw query sent to Prometheus.
2.  **Check Prometheus Active Queries:**
    Open the Prometheus Web UI and go to `Status -> Active Queries` to see executing queries.
3.  **Identify Slow PromQL Queries in logs:**
    Search Prometheus server logs for slow queries exceeding standard query execution parameters:
    ```bash
    kubectl logs -n monitoring prometheus-0 -c prometheus | grep "slow query"
    ```

### Resolution
1.  **Optimize Variable Queries:**
    Replace expensive variables query patterns like `label_values({__name__=~".+"}, pod)` with narrow queries:
    ```promql
    # Efficient: retrieves label values strictly from kube-state-metrics
    label_values(kube_pod_info, pod)
    ```
2.  **Enforce Query Range Limits:**
    Edit the Prometheus configuration file to enforce a global query range limit:
    ```yaml
    # In prometheus-deployment arguments
    - "--query.max-concurrency=20"
    - "--query.max-samples=50000000"
    ```
3.  **Rewrite PromQL Aggregations:**
    Ensure aggregations (`sum`, `avg`) are outside the range vector functions:
    *   *Incorrect (Very Slow):* `rate(sum(http_requests_total)[5m])`
    *   *Correct (Fast):* `sum(rate(http_requests_total[5m]))`

### Prevention
*   Enable caching in Grafana datasource config.
*   Deploy Thanos downsampling compaction for long-term range querying.
