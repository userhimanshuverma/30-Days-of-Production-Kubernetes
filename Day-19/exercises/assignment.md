# 🏆 Day 19 Assignment: The Broken Microservices Challenge

## Objective
Apply the SRE troubleshooting methodologies and commands you learned today to diagnose and repair a broken multi-tier microservices application running inside your local cluster.

---

## Scenario Description
A multi-tier application consisting of a `frontend` web service and a `payment-api` backend has been deployed. However, the application is completely unresponsive:
- Customers cannot load the frontend.
- Backend processing is reporting errors.
- Logs show database and service communication failures.

---

## Assignment Instructions

### Step 1: Deploy the Broken Scenario
Save the following manifest configuration as `broken-app.yaml` inside your local cluster directory:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: billing-config
  namespace: default
data:
  DB_HOST: "postgres-svc"
  # Missing: API_KEY (required by payment-api)
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: billing-backend
  template:
    metadata:
      labels:
        app: billing-backend
    spec:
      containers:
      - name: payment-api
        image: python:3.9-slim
        command: ["python", "-c"]
        args:
        - |
          import os, sys, time
          print("Starting Billing API...", flush=True)
          if not os.environ.get("API_KEY"):
              print("FATAL CONFIG ERROR: API_KEY is missing!", file=sys.stderr, flush=True)
              sys.exit(1)
          # Allocate memory block to trigger OOM limits
          sink = []
          for i in range(1, 15):
              print(f"Loading cache chunk {i}...", flush=True)
              sink.append("x" * (4 * 1024 * 1024)) # ~4MB chunk
              time.sleep(0.5)
          print("Billing API is fully initialized.", flush=True)
          while True:
              time.sleep(3600)
        envFrom:
        - configMapRef:
            name: billing-config
        resources:
          limits:
            memory: "30Mi" # Hard limit set too low
          requests:
            memory: "15Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: payment-service
  namespace: default
spec:
  ports:
  - port: 80
    targetPort: 8080 # App is actually listening on port 80 or runs script
  selector:
    app: payment-api # Mismatch: Pods are labeled billing-backend
```

Apply this broken manifest:
```bash
kubectl apply -f broken-app.yaml
```

---

## Your Tasks (What You Must Accomplish)

Analyze the environment and fix all issues:

1.  **Diagnose the CrashLoop:** Find out why `payment-api` is crashing on boot first. Locate the missing configurations and apply them.
2.  **Diagnose the OOMKilled Loop:** After resolving the config loop, you will notice the pods crash again. Confirm that the status is `OOMKilled` (Exit Code 137). Determine a safe memory threshold and apply a patch to the Deployment limits.
3.  **Diagnose the Service Routing:** Ensure that the `payment-service` successfully points to the `payment-api` pod endpoints. Resolve the selector mismatch.
4.  **Confirm Stability:** All pods must show `STATUS: Running` with `READY: 1/1` and `RESTARTS: 0` (or stabilized) for at least 5 minutes.

---

## Submission Checklist
Provide the output of the following commands in your execution logs:
- `kubectl get deployments -o wide`
- `kubectl get endpoints payment-service`
- `kubectl describe pod -l app=billing-backend` (last events section showing healthy liveness/starts).
- A short RCA paragraph explaining what was wrong and how you resolved it.
