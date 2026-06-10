# 🚨 Incident Scenario 4: The Out-of-Sync Config Crash Loop
**Severity:** Sev1 (Degraded Deployment)  
**MTTR:** 19 Minutes  
**Impact:** Frontend web application failed to load new product catalogs.

---

## 1. Alerting & Symptoms
At `18:10:00 UTC`, the SRE team receives alerts from ArgoCD and Kubernetes Event Auditor:
```text
[WARNING] Deployment product-catalog: replica_count_mismatch (expected: 5, running: 2)
[CRITICAL] Pod product-catalog-54bf9d-x12y3: Enter CrashLoopBackOff
```
Only two pods are processing requests; the other three are stuck in a restart loop.

---

## 2. Incident Timeline & Investigation

### 18:12 - Triage Phase
SRE checks the status of the failing deployment:
```bash
kubectl get pods -n production -l app=product-catalog
```
**Output:**
```text
NAME                               READY   STATUS             RESTARTS   AGE
product-catalog-54bf9d-x12y3       0/1     CrashLoopBackOff   4          5m
product-catalog-54bf9d-y34z5       0/1     CrashLoopBackOff   4          5m
product-catalog-54bf9d-z56w7       0/1     CrashLoopBackOff   3          4m
product-catalog-54bf9d-normal1     1/1     Running            0          12d
product-catalog-54bf9d-normal2     1/1     Running            0          12d
```
Three pods are crashing. Two are running fine (which were started 12 days ago). This indicates that new pod initializations are failing, while existing instances are stable.

### 18:14 - Pod Logs Examination
SRE checks the logs of the crashing pod:
```bash
kubectl logs product-catalog-54bf9d-x12y3 -n production
```
**Output:**
```text
[Catalog-Init] Loading config schema...
[Catalog-Init] FATAL: Key 'CATALOG_CDN_URL' is required but is missing or empty.
[Catalog-Init] Process exited with status 1
```
The application crashes immediately upon execution because a mandatory configuration key is missing.

### 18:16 - ConfigMap Analysis
SRE inspects the configmap mounted to the catalog pods:
```bash
kubectl describe configmap catalog-config -n production
```
**Output:**
```yaml
Data:
  CATALOG_DB_HOST: "prod-db.internal"
  CATALOG_FEATURES: "search,cart"
  # CATALOG_CDN_URL is not present
```
SRE checks the git log for recent config changes. 
A GitOps PR was merged 15 minutes ago adding `CATALOG_CDN_URL` requirement to the application code, but the ConfigMap deployment in Kubernetes was delayed or failed to include the key.

---

## 3. Root Cause Analysis (5 Whys)

1. **Why did the frontend catalog fail to load new items?** Three out of five backend pods crashed, reducing catalog capacity.
2. **Why did they crash?** The application failed schema verification on startup because `CATALOG_CDN_URL` was missing.
3. **Why was it missing?** The environment variable mapping in the deployment matched a key in `catalog-config` ConfigMap that did not exist.
4. **Why did this mismatch occur?** The application code change requiring the CDN URL was deployed via CI before the GitOps repository updated the config map template.
5. **Why were old pods still running?** ConfigMaps are read at pod startup. Existing pods did not restart, meaning they retained the older configuration in RAM.

---

## 4. Mitigation & Resolution
*   **18:22 UTC:** SRE patches the ConfigMap directly to append the missing key:
    ```bash
    kubectl patch configmap catalog-config -n production --type merge -p '{"data":{"CATALOG_CDN_URL":"https://cdn.production.internal"}}'
    ```
*   **18:25 UTC:** SRE deletes the crashing pods to trigger a clean restart:
    ```bash
    kubectl delete pods -n production -l app=product-catalog --field-selector status.phase=Failed
    ```
*   **18:29 UTC:** All 5 pods boot up successfully and transition to `Running` (Ready: `1/1`). The outage is resolved.

---

## 5. Prevention Action Items
*   **Helm / Kustomize Integration:** Link ConfigMap hashes directly to the Deployment spec template annotations:
    ```yaml
    annotations:
      checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    ```
    This forces a rolling update only when the config is successfully applied, preventing out-of-sync configurations.
*   **Validation Webhooks:** Deploy a validation webhook that checks deployment configurations against ConfigMap schema definitions.
