# 🛠️ Lab 4: Configuring Alerts & Incident Response

In this lab, you will deploy Alertmanager, configure notification routing, trigger a simulated application incident (injecting HTTP 5xx errors), watch the alert lifecycle transition from PENDING to FIRING, and configure a silence rule to manage alert noise.

---

## Step 1: Deploy Alertmanager
Alertmanager requires a config containing receiver configurations (Slack, webhook, PagerDuty) and routing trees.

Apply the Alertmanager ConfigMap and Deployment manifests:
```bash
kubectl apply -f ../manifests/alertmanager-config.yaml
kubectl apply -f ../manifests/alertmanager-deployment.yaml
```

Verify the pod is running:
```bash
kubectl get pods -n monitoring -l app=alertmanager
```

---

## Step 2: Connect Prometheus to Alertmanager
Prometheus must know the network address of the Alertmanager service. Verify that the `prometheus-config.yaml` file contains the following block under `alerting`:
```yaml
    alerting:
      alertmanagers:
        - static_configs:
            - targets:
                - "alertmanager:9093"
```

If you deployed Prometheus before Alertmanager, reload Prometheus's configuration to establish connectivity:
```bash
kubectl exec -it statefulset/prometheus -n monitoring -c prometheus -- curl -X POST http://localhost:9090/-/reload
```

---

## Step 3: Inject HTTP Errors to Trigger Alarms
We will simulate a production incident. The sample application `customer-api` (Podinfo) has a built-in error endpoint (`/status/500`) which forces HTTP 500 error responses.

1.  Deploy a temporary loader container to flood the service with 500 errors:
    ```bash
    kubectl run siege-loader --image=alpine --restart=Never -n default -- \
      sh -c "while true; do wget -qO- http://customer-api:9898/status/500; sleep 0.1; done"
    ```
2.  Open the Prometheus Web UI (port-forward `9090`) and check the **Alerts** tab.
3.  Within 1-2 minutes, you will see the **HttpErrorSpike** alert transition into the light-yellow **PENDING** state. This means the threshold was breached, but the duration requirement (`for: 3m`) has not yet elapsed.
4.  Once the error condition persists past 3 minutes, the alert turns red **FIRING**. Prometheus now pushes the alert payload to Alertmanager.

---

## Step 4: Trace Alertmanager Routing & Set Silences
1.  Port-forward Alertmanager to view the dashboard:
    ```bash
    kubectl port-forward svc/alertmanager 9093:9093 -n monitoring
    ```
2.  Open [http://localhost:9093](http://localhost:9093) in your browser.
3.  You will see the active `HttpErrorSpike` alert.
4.  **Create a Silence:** To prevent notification noise while diagnosing the root cause, click the **Silence** button next to the alert, fill in the metadata (e.g., your name, issue ticket reference), and click **Create**. This mutes outbound pages.
5.  **Clean up / Resolve the incident:** Delete the loader container to stop error generation:
    ```bash
    kubectl delete pod siege-loader -n default
    ```
6.  Watch the Prometheus Alerts page. As error counts fall back to zero, the alert will return to the green **INACTIVE** state, and Alertmanager will send a RESOLVED event notification.
