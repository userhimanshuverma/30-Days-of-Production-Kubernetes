# 🛠️ Lab 3: Configuring Exporters & Application Monitoring

In this lab, you will install exporters to collect hardware and cluster resource metrics, deploy a sample application, and configure Prometheus relabeling rules to dynamically discover and scrape application metrics.

---

## Step 1: Deploy Node Exporter (DaemonSet)
Node Exporter requires system-level namespace mounting to read host parameters.

Apply the Node Exporter manifest:
```bash
kubectl apply -f ../manifests/node-exporter.yaml
```

Verify that a daemonset pod is running on every node:
```bash
kubectl get daemonset node-exporter -n monitoring
kubectl get pods -n monitoring -l app=node-exporter
```

Test query the exporter from the cluster to ensure it returns raw OpenMetrics plaintext:
```bash
kubectl exec -it prometheus-0 -n monitoring -- curl http://localhost:9100/metrics | head -n 15
```

---

## Step 2: Deploy kube-state-metrics
Deploy kube-state-metrics to expose cluster state statistics (replicas status, node conditions, resources configurations).

Apply the deployment:
```bash
kubectl apply -f ../manifests/kube-state-metrics.yaml
```

Verify readiness:
```bash
kubectl get deployment kube-state-metrics -n monitoring
```

---

## Step 3: Deploy Application & Verify Service Discovery
We deploy a sample app named `customer-api` (using Podinfo) inside the `default` namespace. We add annotations in the pod template to tell Prometheus to scrape it:

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9898"
  prometheus.io/path: "/metrics"
```

Apply the sample application:
```bash
kubectl apply -f ../manifests/sample-app.yaml
```

Verify pods are running:
```bash
kubectl get pods -n default -l app=customer-api
```

---

## Step 4: Verify Discovery in Prometheus Targets
1.  Open the Prometheus Web UI (port-forward `9090` if not active).
2.  Navigate to **Status -> Targets**.
3.  Scroll to the **kubernetes-pods** scrape job.
4.  You will find two entries matching the `customer-api` pod IPs at port `9898` in `UP` status.
5.  In the query bar, run:
    ```promql
    http_requests_total{kubernetes_pod_name=~"customer-api-.*"}
    ```
    You will see the active HTTP request counters exposed by Podinfo, split by method and response code.
