# 🚨 Incident Scenario 1: The Cascading Database Outage
**Severity:** Sev0 (Critical Site Outage)  
**MTTR:** 42 Minutes  
**Impact:** 100% Checkout Failures globally

---

## 1. Alerting & Symptoms
At `14:02:15 UTC`, the PagerDuty on-call SRE was alerted with:
```text
[CRITICAL] Service checkout-api: http_error_rate_5xx > 15% (current: 98%)
```
At the same time, customer support reports a surge in checkout failures with "Internal Server Error" screens.

---

## 2. Incident Timeline & Investigation

### 14:05 - Triage Phase
The SRE logs into the cluster and checks pod health:
```bash
kubectl get pods -n production
```
**Output:**
```text
NAME                                READY   STATUS    RESTARTS   AGE
checkout-api-8c76bf95-aa12b        1/1     Running   0          4h
checkout-api-8c76bf95-bb45c        1/1     Running   0          4h
postgres-db-0                       1/1     Running   0          182d
```
All pods are reported as `Running`. The issue is not a crash loop or OOM kill.

### 14:10 - Logs Inspection
The SRE inspects the logs of one of the checkout pods:
```bash
kubectl logs -f deployment/checkout-api -n production --tail=50
```
**Output:**
```json
{"time":"2026-06-10T14:08:12Z","level":"ERROR","trace_id":"9a8b12f45e76","msg":"Database operation failed","error":"dial tcp 10.96.14.88:5432: i/o timeout"}
{"time":"2026-06-10T14:08:14Z","level":"ERROR","trace_id":"8a9f234bc562","msg":"Failed to checkout","error":"sql: database/sql: connection pool exhausted"}
```
The application is reporting connection pool exhaustion and database TCP timeouts.

### 14:18 - Database Diagnostics
The SRE checks the postgres database metrics and logs:
```bash
kubectl logs statefulset/postgres-db -n production --tail=10
```
**Output:**
```text
2026-06-10 14:15:30.412 UTC [42] FATAL:  remaining connection slots are reserved for non-replication superuser connections
2026-06-10 14:15:31.114 UTC [43] FATAL:  remaining connection slots are reserved for non-replication superuser connections
```
The database has run out of connection slots (`max_connections` limit reached).

---

## 3. Root Cause Analysis (5 Whys)

1. **Why did checkouts fail?** The API pods could not communicate with the database.
2. **Why?** The database hit its limit of 500 maximum connections.
3. **Why?** The checkout API pods were opening new connections without closing existing ones.
4. **Why?** A recent code deploy (v2.3.1) introduced a defer block error in the transaction handler (`sql.Rows` was never closed).
5. **Why?** The linting rules in CI did not check for unclosed SQL rows/connections.

---

## 4. Mitigation & Resolution
*   **14:28 UTC:** SRE rolls back the API deployment to v2.3.0:
    ```bash
    kubectl rollout undo deployment/checkout-api -n production
    ```
*   **14:32 UTC:** SRE terminates existing idle sessions on PostgreSQL to free up slots:
    ```bash
    kubectl exec -it statefulset/postgres-db -n production -- psql -U postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle';"
    ```
*   **14:35 UTC:** API connections normalize, error rates drop to 0%, and SLA is restored.

---

## 5. Prevention Action Items
*   **CI Validation:** Add static code analyzer (`sqlclosecheck`) to block builds with unclosed rows or transactions.
*   **Pooling Middleware:** Deploy `PgBouncer` as a sidecar or standalone deployment between API and DB to handle connection multiplexing.
*   **Alerting:** Set up Prometheus alerts for Postgres connection saturation (>85% of `max_connections`).
