# 🚨 Day 5: Deployment & Rollout Troubleshooting Playbook

This playbook provides actionable triaging runbooks for the 10 most common rollout and reconciliation failures encountered in production Kubernetes environments.

---

## 🔍 Triage Cheat Sheet: Key Commands
When a deployment is unhealthy, execute these triage commands immediately:

```bash
# 1. Check rollout progress and deadline status
kubectl rollout status deployment/<deployment-name>

# 2. Get deployment status conditions (look for Progressing/Available failures)
kubectl describe deployment/<deployment-name>

# 3. List all pods associated with the deployment's labels
kubectl get pods -l <selector-label-key>=<selector-label-val>

# 4. View container termination events and states
kubectl describe pod/<pod-name>

# 5. Check cluster scheduling and volume events
kubectl get events --sort-by=.metadata.creationTimestamp

# 6. View container logs (include --previous for crash investigations)
kubectl logs pod/<pod-name> --previous
```

---

## 🛠️ Runbooks: 10 Production Failure Scenarios

### Scenario 1: Stuck Rollouts
* **Symptoms**: `kubectl rollout status` hangs indefinitely. Replicas are stuck under-replicated.
* **Root Cause**: A newly spawned pod cannot reach the `Ready` state, preventing the deployment controller from scaling down old pods (due to `maxUnavailable` budgets).
* **Investigation**:
  1. Run `kubectl rollout status deployment/<name>`. Note the progress.
  2. Run `kubectl get pods -l app=<app>` and look for Pods with `0/1` READY.
  3. Run `kubectl describe pod <stuck-pod>` and inspect the `Events` section at the bottom.
* **Resolution**:
  - If a probe is failing, fix the probe path, port, or server config.
  - If the image tag is wrong, apply the corrected tag.
  - To resume operation immediately, abort and roll back with `kubectl rollout undo deployment/<name>`.
* **Prevention**: Set a reasonable `progressDeadlineSeconds` (e.g., `120` or `300`). This ensures the deployment transitions to `Failed` instead of hanging forever, allowing CI/CD systems to catch it and self-abort.

---

### Scenario 2: Failed Rolling Updates (Resource Starvation Hangs)
* **Symptoms**: The update triggers, creates exactly one new pod, and then freezes. The new pod is stuck in `Pending`.
* **Root Cause**: The cluster does not have enough CPU or Memory capacity to schedule the new "surge" pod, and because `maxUnavailable: 0` is set, the scheduler cannot terminate any old pods to free up node space.
* **Investigation**:
  1. Run `kubectl get events --sort-by=.metadata.creationTimestamp`.
  2. Look for scheduler events: `FailedScheduling: 0/3 nodes are available: 3 Insufficient cpu.`
* **Resolution**:
  - Add more worker nodes or scale up node groups.
  - Temporarily lower the Deployment resource requests.
  - Set `maxUnavailable: 1` if your application can afford a temporary capacity drop during rollout.
* **Prevention**: Implement a cluster-autoscaler or Karpenter. Avoid setting CPU requests to peak usage; set requests to typical baseline usage and let limits handle burst peaks.

---

### Scenario 3: ReplicaSet Label Selector Mismatch
* **Symptoms**: Applying a deployment manifest returns: `Field is immutable: spec.selector`. Or, applying a manifest succeeds but old Pods are not terminated, resulting in double the desired replica count.
* **Root Cause**: Attempting to modify `spec.selector` on an active Deployment (which is forbidden after creation), or selecting a broad label that collides with another deployment's selector.
* **Investigation**:
  1. Run `kubectl describe deployment <name>`. Check the Selector label.
  2. Check if another deployment shares the same selector: `kubectl get deployments -A -o wide`.
* **Resolution**:
  - If you must change selectors, delete the deployment resource first using `kubectl delete deployment <name> --cascade=orphan` (orphans the pods), update the manifest, and re-apply.
* **Prevention**: Always namespace label selectors cleanly (e.g. including `app.kubernetes.io/name: <app-name>`).

---

### Scenario 4: Pods Not Becoming Ready (Probe Mismatch)
* **Symptoms**: Pods are running (`STATUS: Running`) but the readiness column remains `0/1`. Traffic is not routed to them.
* **Root Cause**: The `readinessProbe` is targeting the wrong port, wrong HTTP path (e.g. `/healthz` instead of `/actuator/health`), or the application server requires more boot time than the probe grace limits allow.
* **Investigation**:
  1. Run `kubectl describe pod <pod-name>`.
  2. Look for events: `Warning Unhealthy Readiness probe failed: HTTP probe failed with statuscode: 404`.
* **Resolution**:
  - Correct the path/port in the probe spec.
  - Increase the `initialDelaySeconds` or use a `startupProbe` to shield the readiness probe during boot.
* **Prevention**: Standardize health check endpoints across teams (e.g. `/healthz` is always the readiness endpoint).

---

### Scenario 5: CrashLoopBackOff During Rollout
* **Symptoms**: Pods crash immediately upon start. Status is `CrashLoopBackOff` or `Error`.
* **Root Cause**: Missing environment variables, database credentials, database migration errors, or permissions problems inside the container.
* **Investigation**:
  1. Run `kubectl logs <pod-name> --previous` to see what printed to stdout/stderr right before the crash.
  2. Inspect container exit code: `kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].state.waiting.message}'`.
* **Resolution**:
  - Mount missing ConfigMaps or Secrets.
  - Repair the application code or settings and roll out the fix.
* **Prevention**: Validate application configurations at boot time and exit with descriptive logs. Use init containers to block main container start until dependencies (DB, caches) are reachable.

---

### Scenario 6: Canary Traffic Routing Failure
* **Symptoms**: Traffic is routing unevenly (e.g. 50/50 instead of 90/10) or all traffic is going to the stable version.
* **Root Cause**: The Service selector does not match the canary deployment labels, or the ratio of stable vs canary replicas is incorrect.
* **Investigation**:
  1. Run `kubectl get endpoints <service-name>` and check the list of IPs.
  2. Verify that the sum matches: `Replicas (Stable) + Replicas (Canary)`.
* **Resolution**:
  - Correct the common label on the Canary Deployment template.
  - Adjust replica count values to meet your target ratio (e.g., 9 stable and 1 canary for a 10% split).
* **Prevention**: Use an ingress controller or service mesh (like Istio or Linkerd) for L7 header/percentage traffic splitting instead of depending on Pod replica ratios.

---

### Scenario 7: Rollback Fails (Missing History or DB conflicts)
* **Symptoms**: Running `kubectl rollout undo` returns: `no rollout history found`. Or, rolling back succeeds but pods crashloop immediately.
* **Root Cause**: `spec.revisionHistoryLimit` was set to `0` (disabling history storage), or a database schema update applied by the new version is incompatible with the older version's code.
* **Investigation**:
  1. Check history: `kubectl rollout history deployment/<name>`.
  2. Check logs: `kubectl logs <rolled-back-pod>`. Look for database schema errors.
* **Resolution**:
  - Set database configurations backward-compatible, or apply a database migration restore script.
  - Re-apply the old manifest configuration file manually using Git history.
* **Prevention**: Always set `revisionHistoryLimit` to at least `5`. Follow the Expand/Contract database migration pattern.

---

### Scenario 8: Image Update Failures (ImagePullBackOff)
* **Symptoms**: Pods are stuck in `ImagePullBackOff` or `ErrImagePull`.
* **Root Cause**: Typo in the image name/tag, private registry credentials expired/missing, or registry service outage.
* **Investigation**:
  1. Run `kubectl describe pod <pod-name>`.
  2. Inspect the events: `Failed to pull image: rpc error: code = Unknown desc = Error response from daemon: manifest for my-app:1.2.0-typo not found`.
* **Resolution**:
  - Fix the image tag in the deployment spec.
  - Create and attach the correct `imagePullSecrets` to the service account or pod spec.
* **Prevention**: Integrate image scanning and linting in CI pipelines. Avoid manual kubectl edits.

---

### Scenario 9: Resource Exhaustion (OOMKilled)
* **Symptoms**: Pod starts up, serves a few requests, and terminates with `OOMKilled` (Exit code 137). Rollout stalls.
* **Root Cause**: The memory limit (`spec.containers[0].resources.limits.memory`) is set lower than the application's actual memory requirement.
* **Investigation**:
  1. Run `kubectl describe pod <pod-name>`.
  2. Look for: `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`.
* **Resolution**:
  - Increase the memory limit in the deployment spec.
  - Check the application code for memory leaks.
* **Prevention**: Load-test application components to understand their baseline and peak memory demands before setting production limits.

---

### Scenario 10: Node Disruption During Deployment
* **Symptoms**: Rollout freezes. Several pods are in `NodeLost` or `Terminating` states.
* **Root Cause**: The node hosting the active/surge pods went offline, had a network cut, or was abruptly terminated.
* **Investigation**:
  1. Check node statuses: `kubectl get nodes`.
  2. Check pod scheduling: `kubectl get pods -o wide`. Inspect which nodes host the unready pods.
* **Resolution**:
  - If a node is down, the deployment controller will automatically reschedule pods to healthy nodes once the eviction timeout (default 5m) expires.
  - To accelerate recovery, manually delete the stalled pods using `kubectl delete pod <pod-name> --grace-period=0 --force` (do this with caution).
* **Prevention**: Configure Pod Anti-Affinity rules to prevent scheduling all replicas on the same node or in the same AZ.
