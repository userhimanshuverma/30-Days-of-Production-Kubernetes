# 🧪 Lab 5: Analyze Kubernetes Events

## Objective
Learn how to use Kubernetes cluster events as an event-driven telemetry source to diagnose transient failures, scheduler constraints, and pod life-cycle failures.

---

## Step-by-Step Investigation

### 1. View Namespace Events
By default, running `kubectl get events` lists all events in the current namespace. Run it:
```bash
kubectl get events
```

### 2. Sort Events by Time
Events are returned unordered by default. Sort them so the latest occurrences appear at the bottom:
```bash
kubectl get events --sort-by='.metadata.creationTimestamp'
```

### 3. Filter Event Warnings
To filter out standard lifecycle events (e.g. `Scheduled`, `Pulling`, `Pulled`) and only display issues/errors:
```bash
kubectl get events --field-selector type=Warning --sort-by='.metadata.creationTimestamp'
```

**Expected Output (if there are active issues):**
```text
LAST SEEN   TYPE      REASON             OBJECT                                MESSAGE
1m          Warning   FailedScheduling   pod/payment-worker-8d8a7c-abc12       0/3 nodes are available: 3 Insufficient memory.
15s         Warning   BackOff            pod/payment-processor-597b489d89-9a12b Back-off restarting failed container
```

### 4. Continuous Event Tailing
To monitor events in real-time as they occur (ideal during live upgrades or deployment verification):
```bash
kubectl get events -w
```

---

## Exercise: Trace Pod Schedule Failures
To simulate a scheduling issue due to resource request over-provisioning:

1. Create a temporary pod manifest that requests a massive amount of memory (e.g., `500Gi` RAM):
   ```bash
   kubectl run test-heavy-pod --image=nginx --requests='memory=500Gi' --dry-run=client -o yaml > heavy-pod.yaml
   ```
2. Apply it:
   ```bash
   kubectl apply -f heavy-pod.yaml
   ```
3. Watch the namespace events for the schedule failure:
   ```bash
   kubectl get events --field-selector type=Warning --sort-by='.metadata.creationTimestamp' | grep heavy-pod
   ```
   **Expected Message:**
   `0/3 nodes are available: 3 Insufficient memory.`
4. Clean up:
   ```bash
   kubectl delete pod test-heavy-pod
   ```
