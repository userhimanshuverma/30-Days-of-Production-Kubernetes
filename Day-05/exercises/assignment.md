# 🏆 Day 5 Challenge: Production Workload Tuning & Safe Rollouts

## 🎯 Goal
Your challenge is to take a basic application deployment and optimize it for enterprise-level production standards. You will enforce strict rollouts, implement high-availability affinity rules, configure health checks, restrict security privileges, and test a manual rollback.

---

## 📋 Challenge Requirements

Create a new file named `assignment-deployment.yaml` in this `exercises/` folder and implement the following specifications:

1. **Replicas**: Configure the deployment to run exactly **4 replicas**.
2. **Strategy**: Set the strategy to `RollingUpdate` with a budget that guarantees:
   - At least 4 ready pods are available at all times (`maxUnavailable` calculation).
   - Up to 2 extra pods can be created during the rollout (`maxSurge` calculation).
3. **Anti-Affinity**: Implement a **Pod Anti-Affinity** rule to ensure that the scheduler prefers placing Pods on different physical nodes (use topology key `kubernetes.io/hostname`).
4. **Probes**:
   - Add a `startupProbe` targeting `/` on port `8080` (use `nginxinc/nginx-unprivileged:1.25-alpine`). Give it 5 attempts with a 5-second period.
   - Add a `readinessProbe` targeting `/` on port `8080` that checks every 5 seconds.
   - Add a `livenessProbe` targeting `/` on port `8080` that checks every 10 seconds.
5. **Resources**: Enforce the following limits:
   - Requests: `CPU: 50m`, `Memory: 64Mi`
   - Limits: `CPU: 150m`, `Memory: 128Mi`
6. **Security Hardening**:
   - Set container `runAsNonRoot: true`.
   - Set container `runAsUser: 101` and `runAsGroup: 101`.
   - Set `readOnlyRootFilesystem: true`.
   - Drop all capabilities (`capabilities.drop: ["ALL"]`).
   - **Important Volume Mounts:** Because `nginxinc/nginx-unprivileged` needs to write to temp files (cache, logs, PID marker), you must mount `emptyDir` volumes on `/tmp`, `/var/run`, and `/var/cache/nginx`. If these are omitted, the container will instantly fail to start.

---

## 📝 Manifest Template
Use this template to build your solution. Save it as `exercises/assignment-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api-production
  namespace: default
  labels:
    app.kubernetes.io/name: payment-api
    app.kubernetes.io/tier: backend
spec:
  # 1. Fill in Replicas and Revision History Limit
  # 2. Fill in RollingUpdate Strategy spec
  selector:
    matchLabels:
      app: payment-api
  template:
    metadata:
      labels:
        app: payment-api
    spec:
      # 3. Fill in Pod Anti-Affinity Spec here
      # 6. Fill in Pod-Level SecurityContext
      containers:
      - name: payment-api
        image: nginxinc/nginx-unprivileged:1.25-alpine
        # 6. Fill in Container-Level SecurityContext (readOnlyRootFilesystem, drop capabilities)
        # 5. Fill in CPU and Memory Requests and Limits
        # 4. Fill in Startup, Readiness, and Liveness Probes
        # Hint: Add volumeMounts here for /tmp, /var/run, and /var/cache/nginx
      # Hint: Define the matching emptyDir volumes here at the pod spec level
```

---

## 🔍 Validation Steps

Once you have written and saved your manifest, run the following steps to verify your implementation:

### 1. Apply the manifest
```bash
kubectl apply -f assignment-deployment.yaml
```

### 2. Verify replica distribution across nodes
Check if pods are scheduled on different nodes:
```bash
kubectl get pods -o wide -l app=payment-api
```
*(If you are running a multi-node cluster, verify that the pods are running on separate worker nodes).*

### 3. Verify security contexts are active
Run this command to check if the root filesystem is read-only:
```bash
kubectl exec -it $(kubectl get pods -l app=payment-api -o jsonpath='{.items[0].metadata.name}') -- touch /tmp/test-file
# This should succeed since /tmp is typically writable or mounted as emptyDir.

kubectl exec -it $(kubectl get pods -l app=payment-api -o jsonpath='{.items[0].metadata.name}') -- touch /usr/share/nginx/html/test-file
# This MUST fail with: "touch: /usr/share/nginx/html/test-file: Read-only file system".
```

### 4. Trigger an update and watch rollout constraints
In one terminal, run:
```bash
kubectl get pods -l app=payment-api -w
```
In another terminal, trigger an update:
```bash
kubectl set image deployment/payment-api-production payment-api=nginxinc/nginx-unprivileged:1.26-alpine
```
Verify that:
- Exactly 2 new pods are created at the start of the rollout (representing `maxSurge: 2`).
- No old pods are terminated until the new pods are fully ready (representing `maxUnavailable: 0`).

---

## 🏆 Submission Check
Your challenge is successful if:
* The manifest validates and applies without API errors.
* No pods are scheduled on the same node (if resources permit).
* Writing to the container root folder returns a "Read-only file system" error.
* The rolling update creates exactly two surge pods at the beginning of the update.
