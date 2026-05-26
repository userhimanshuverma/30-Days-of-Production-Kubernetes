# 🛠️ Lab 5: Tuning Health Probes & Failure Scenarios
## 30 Days of Production Kubernetes — Day 4

In this lab, you will explore how Kubernetes monitors container health. You will deploy a Pod with Startup, Liveness, and Readiness probes configured, observe its startup behavior, and inject a failure to see how Kubernetes isolates and heals the workload.

---

## 🎯 Lab Objectives
1. Understand the difference between Startup, Liveness, and Readiness probes.
2. Deploy a Pod with custom health checks.
3. Observe how Startup probes protect the initialization sequence.
4. Perform failure injection to trigger container restart and traffic isolation.

---

## 🛠️ Step-by-Step Guide

### Step 1: Deploy the Probed Pod
Apply the manifest file `manifests/05-probe-tuning.yaml`:
```bash
kubectl apply -f manifests/05-probe-tuning.yaml
```

**Expected Output:**
```text
pod/probed-service created
```

### Step 2: Observe Initial Probe Behavior
Immediately check the Pod details:
```bash
kubectl describe pod probed-service
```

Look at the **Events** list at the bottom. You will notice that initially, the liveness and readiness probes do not execute. Only the **Startup Probe** runs. Once the startup probe succeeds (Nginx responds HTTP 200), the liveness and readiness loops are activated.

### Step 3: Verify the Pod is serving traffic
Wait until the Pod is fully ready:
```bash
kubectl get pods
```

**Expected Output:**
```text
NAME             READY   STATUS    RESTARTS   AGE
probed-service   1/1     Running   0          30s
```
The `READY` column shows `1/1`, indicating that the readiness probe has passed and the Pod is active in the Service endpoint list.

---

## 💥 Step 4: Inject a Failure (Hands-on Experiment)

Our probes are configured to check the path `/` on port `8080`. If Nginx cannot serve the root page, the probes will fail. Let's delete the default `index.html` file to simulate a localized application failure (e.g. cache corrupted or main page missing).

1. **Delete the Nginx root file:**
   ```bash
   kubectl exec probed-service -- rm /usr/share/nginx/html/index.html
   ```

2. **Immediately watch the Pod status:**
   ```bash
   kubectl get pods -w
   ```

3. **Check the Kubelet events:**
   ```bash
   kubectl describe pod probed-service
   ```

**Expected Output Log & Events:**
After about 10 seconds (the readiness probe checks every 10s), the readiness probe fails because Nginx returns a `403 Forbidden` response instead of a `200 OK`.
```text
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Warning  Unhealthy  12s (x2 over 22s)  kubelet            Readiness probe failed: HTTP probe failed with statuscode: 403
```

Check the Pod status again:
```text
NAME             READY   STATUS    RESTARTS   AGE
probed-service   0/1     Running   0          1m
```
Notice that the Pod status remains `Running` (it has NOT restarted yet), but the `READY` column has dropped to `0/1`. This means the Kubelet has isolated the Pod, removing its IP from any Service load balancers to prevent users from seeing errors.

---

## 🔄 Step 5: Triggering Liveness Probe & Automatic Recovery

Because we deleted the file, the **Liveness Probe** is also failing.
After 3 consecutive failures (our `failureThreshold: 3` for liveness), the Kubelet concludes that the container is deadlocked/unrecoverable and triggers a restart.

Watch the status:
```text
NAME             READY   STATUS    RESTARTS   AGE
probed-service   0/1     Running   0          1m25s
probed-service   0/1     Running   1 (10s ago) 1m30s
probed-service   1/1     Running   1          1m45s
```
* **What happened?**
  1. Kubelet detected the liveness probe failure.
  2. Kubelet sent a `SIGTERM` followed by a `SIGKILL` to the Nginx process.
  3. The container was recreated from the base image.
  4. Because the image layers are immutable, the new container starts with a fresh, healthy `/usr/share/nginx/html/index.html` file.
  5. The startup probe succeeds, followed by the readiness probe, and the Pod is restored to `1/1 READY`!

This demonstrates how Kubernetes self-heals application crashes automatically in production.

### Step 6: Clean Up
```bash
kubectl delete -f manifests/05-probe-tuning.yaml
```
