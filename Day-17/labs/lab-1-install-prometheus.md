# 🛠️ Lab 1: Installing and Configuring Prometheus

In this lab, you will deploy an enterprise-grade Prometheus Server instance in your Kubernetes cluster, configure RBAC permissions to query system endpoints, mount scrape settings, and access the Prometheus Web UI.

---

## Prerequisites
*   A running Kubernetes cluster (Kind, Minikube, or custom cloud cluster).
*   `kubectl` CLI configured on your workstation.

---

## Step 1: Create the Monitoring Namespace & RBAC
Prometheus requires permissions to poll nodes, endpoints, and pods from the API Server. We will isolate the monitoring stack in the `monitoring` namespace.

Apply the namespace and RBAC configurations:
```bash
kubectl apply -f ../manifests/prometheus-rbac.yaml
```

Verify that the namespace, ServiceAccount, and cluster bindings are created:
```bash
kubectl get sa -n monitoring
kubectl describe clusterrole prometheus
```

---

## Step 2: Configure Scrape Rules (ConfigMap)
The Prometheus Configuration (`prometheus.yml`) is stored in a ConfigMap. This defines scrape jobs for service discovery.

Inspect the scrape configuration inside `../manifests/prometheus-config.yaml`. Notice how the `kubernetes-nodes` job uses relabel rules to scrape metrics via the API Server proxy:
```yaml
      - job_name: "kubernetes-nodes"
        scheme: https
        tls_config:
          ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          insecure_skip_verify: true
...
```

Apply the ConfigMap manifest:
```bash
kubectl apply -f ../manifests/prometheus-config.yaml
```

---

## Step 3: Deploy Prometheus (StatefulSet)
To ensure metric data persists across restarts, we deploy Prometheus as a `StatefulSet` bound to a Persistent Volume.

Apply the deployment manifest:
```bash
kubectl apply -f ../manifests/prometheus-deployment.yaml
```

Wait for the Pod to reach the running state:
```bash
kubectl get pods -n monitoring -w
```

If your local dev cluster does not support automatic PV provisioning (e.g. standard Kind config without default storage class), you can modify the volume mounts in `prometheus-deployment.yaml` to use an `emptyDir` volume instead of the `volumeClaimTemplates` block for temporary development testing.

---

## Step 4: Verify Scrape target and Web UI Access
With the server running, port-forward the port `9090` to access the console:

```bash
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
```

Open [http://localhost:9090](http://localhost:9090) in your web browser.

1.  Navigate to **Status -> Targets**.
2.  Ensure that the `prometheus` local target is active and showing green status (`UP`).
3.  Go to **Status -> Configuration** to verify that your scrape rules loaded successfully.
4.  Switch to the **Graph** page, type `prometheus_tsdb_head_series` in the query bar, and click **Execute**. You will see the active time-series count currently tracked in memory.
