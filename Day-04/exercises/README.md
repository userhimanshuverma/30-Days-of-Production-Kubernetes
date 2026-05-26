# 🏆 Day 4 Daily Challenge: The Enterprise Pod
## 30 Days of Production Kubernetes — Day 4

In this challenge, you will design and write a single, production-hardened Pod manifest that implements advanced initialization, sidecar patterns, security context hardening, and customized probes.

---

## 🎯 Challenge Requirements

You must create a YAML file named `enterprise-pod-challenge.yaml` that defines a Pod meeting the following technical requirements:

### 1. Metadata and Scheduling
* **Pod Name:** `enterprise-auth-service`
* **Namespace:** `default`
* **Labels:** 
  * `app: auth-engine`
  * `tier: backend`
  * `environment: production`

### 2. Init Container (Pre-flight Dependency check)
* **Name:** `init-db-check`
* **Image:** `busybox:1.36`
* **Logic:** The init container must run a loop checking if `postgres-auth-service` is reachable on port `5432`. It should loop and check every 2 seconds, only exiting successfully when the port is open.
* **Resources:** Set requests/limits (`50m` CPU / `64Mi` memory).

### 3. Main Application Container
* **Name:** `auth-app`
* **Image:** `nginxinc/nginx-unprivileged:alpine` (runs on port 8080 by default)
* **Ports:** Expose port `8080` as `http`.
* **Shared Storage:** Mount a volume named `log-storage` at `/var/log/nginx/`.
* **Security Context (Hardening):**
  * `runAsNonRoot: true`
  * `runAsUser: 10001`
  * `allowPrivilegeEscalation: false`
  * `readOnlyRootFilesystem: false` (note: nginx-unprivileged writes temporary files, but keep it secure. Actually, set `readOnlyRootFilesystem: true` and mount an extra emptyDir for `/tmp` and `/var/cache/nginx` to achieve absolute gold-standard security!)
* **Probes:**
  * **Startup Probe:** Checking path `/` on port `8080`. Allows up to 60 seconds to start (period 10s, failure threshold 6).
  * **Liveness Probe:** Checking path `/` on port `8080` every 20 seconds.
  * **Readiness Probe:** Checking path `/` on port `8080` every 10 seconds.
* **Resources:** Requests `100m` CPU / `128Mi` RAM. Limits `200m` CPU / `256Mi` RAM.

### 4. Logging Sidecar Container
* **Name:** `log-shipper`
* **Image:** `alpine:latest`
* **Logic:** Mount the `log-storage` volume as **read-only** at `/var/log/app/`. Run a shell command that tails `/var/log/app/access.log` and prints it to standard output.
* **Resources:** Requests `50m` CPU / `64Mi` RAM. Limits `100m` CPU / `128Mi` RAM.

### 5. Volumes
* **Volume 1 (Shared):** `log-storage` of type `emptyDir` (in-memory `medium: Memory` is optional but recommended).
* **Volume 2 & 3 (Nginx write targets if Read-Only Root FS):** `tmp-dir` and `cache-dir` of type `emptyDir` so Nginx can write temp cache files.

---

## 🛠️ Verification Steps

Once you write the manifest, you can test it in your local Kind or Minikube cluster:

1. **Apply the mock database service:**
   Create a temporary service so the init container can eventually succeed.
   ```bash
   kubectl run mock-db --image=hashicorp/http-echo:latest --port=5432 -l app=db-backend
   kubectl expose pod mock-db --name=postgres-auth-service --port=5432 --target-port=5432
   ```

2. **Apply your challenge Pod:**
   ```bash
   kubectl apply -f enterprise-pod-challenge.yaml
   ```

3. **Verify lifecycle transitions:**
   Observe the transitions using `kubectl get pods -w`. You should see the Pod start in `Init:0/1`, then once the mock DB is running, shift to `PodInitializing`, and finally `Running`.

4. **Verify Log streaming:**
   Generate dummy web traffic:
   ```bash
   kubectl port-forward enterprise-auth-service 8080:8080
   curl http://localhost:8080/
   ```
   Check the logs of the sidecar container:
   ```bash
   kubectl logs enterprise-auth-service -c log-shipper
   ```
   You should see Nginx access logs printed by the tail command in the sidecar!

---

## 📝 Submission Guidelines
Write your YAML file in this folder (`Day-04/exercises/enterprise-pod-challenge.yaml`). Ensure it has no syntax errors, validated using `kubectl --dry-run=client -f <file>`.
