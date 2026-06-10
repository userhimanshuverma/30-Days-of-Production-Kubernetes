# 🧪 Lab 8: Investigate Production Incidents

## Objective
Learn how to apply the SRE triage loop to investigate a production-degrading outage where pods are running but users are getting HTTP 5xx errors.

---

## The Scenario
A high-throughput API gateway is reporting a latency spike and HTTP 504 (Gateway Timeout) errors. Downstream services are suspected.

---

## Step-by-Step Investigation Workflow

### Step 1: Trace Ingress Failures
Locate the Ingress Controller name and check its access logs to find where requests are stalling:
```bash
# Get ingress controller pods (assuming ingress-nginx is deployed)
kubectl get pods -n ingress-nginx

# Search for 504 errors in the gateway logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=200 | grep "504"
```
**Example Log Entry:**
```text
192.168.1.1 - - [10/Jun/2026:23:40:02 +0000] "GET /v1/orders HTTP/1.1" 504 182 "-" "Mozilla" 1.998 - [default-order-service-80] - -
```
*The upstream request time took ~2.0 seconds and timed out. The backend service target is default-order-service-80.*

### Step 2: Audit Downstream Pod CPU Throttling
Check if the backend pods are CPU throttled, which causes processing times to exceed proxy timeouts.

1. Check current resource usage:
   ```bash
   kubectl top pods -l app=order-api
   ```
2. Retrieve cgroup limits:
   ```bash
   kubectl get deployment order-api -o jsonpath='{.spec.template.spec.containers[*].resources}'
   ```
3. Audit throttling rate in container metrics (via Prometheus expression or run a debug container to check cpu metrics):
   If CPU limits are `100m` (0.1 CPU core) and the thread pool is handling dozens of requests concurrently, CPU scheduling throttling will trigger.

### Step 3: Triage the Database Bottleneck
If CPU is not throttled, inspect the database connection counts:
```bash
# Connect to your db container and list active client backends
kubectl exec -it statefulset/postgres-db -- psql -U postgres -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"
```
**Expected Output:**
```text
 count | state
-------+--------
   498 | idle in transaction
     2 | active
```
*The output indicates a massive count of "idle in transaction" sessions, meaning the application is leaking connection slots, blocking new checkout requests from executing.*

---

## Resolution & Action
1. Apply the temporary hotfix: increase the max connections in postgres config or scale down and restart the leaking client deployment to force session closures.
2. Draft a post-mortem focusing on the database transaction leak.
