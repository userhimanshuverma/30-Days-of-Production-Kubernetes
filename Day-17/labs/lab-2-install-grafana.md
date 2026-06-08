# 🛠️ Lab 2: Installing and Configuring Grafana

In this lab, you will deploy Grafana to build and display real-time dashboard visualizations, provision the Prometheus datasource automatically, and import standard Kubernetes monitoring dashboards.

---

## Step 1: Deploy Grafana and Datasource Provisioners
To avoid manual datasource setup inside the UI, we utilize Grafana's provisioning engine. The datasource config is saved inside a ConfigMap in `../manifests/grafana.yaml` under `datasources.yaml`:

```yaml
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus:9090
        isDefault: true
```

Apply the Grafana deployment:
```bash
kubectl apply -f ../manifests/grafana.yaml
```

Wait for the deployment to complete:
```bash
kubectl rollout status deployment/grafana -n monitoring
```

---

## Step 2: Access the Grafana UI
Port-forward port `3000` to connect to the dashboard interface:

```bash
kubectl port-forward svc/grafana 3000:3000 -n monitoring
```

Open [http://localhost:3000](http://localhost:3000) in your web browser.

1.  Login with the default administrative credentials:
    *   **Username:** `admin`
    *   **Password:** `admin123`
2.  Go to **Connections -> Data Sources** in the left navigation panel.
3.  Click on the provisioned **Prometheus** datasource and click **Save & Test**. You should see a confirmation saying: *"Data source is working"*.

---

## Step 3: Import Standard Kubernetes Dashboards
Rather than designing dashboards from scratch, you can import standard community designs using their IDs.

1.  In Grafana, click the **+ (Create)** icon in the top right, and select **Import**.
2.  Enter the ID `1860` (Node Exporter Full dashboard) and click **Load**.
3.  Select **Prometheus** in the data source selection box, and click **Import**.
4.  *(Optional)* Repeat the steps to import ID `8685` (kube-state-metrics dashboard) to monitor pod status and deployment metrics.

---

## Step 4: Build a Custom Panel
Now, write your first custom PromQL panel.

1.  Create a new dashboard by clicking **+ -> Dashboard -> Add a new panel**.
2.  In the query field, enter this PromQL query to graph CPU usage by pod:
    ```promql
    sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (pod, namespace)
    ```
3.  In the panel options on the right:
    *   Set **Title** to: `Active Pod CPU Usage Rate`
    *   Set **Unit** to: `Percent (0-1.0)` or `Hertz (ticks)` or `cores` (depending on expression). For raw CPU time rate, core rate is standard. Set Unit to `CPU / cores`.
4.  Click **Apply** in the top right to save the panel to your dashboard.
