# ⚡ Spot Instance Interruption Handling

This guide explains how Spot instance interruptions occur, how node termination controllers handle them, and how to write resilient application workloads that degrade gracefully.

---

## 1. The Interruption Mechanism

Spot instances represent unused cloud compute capacity. When the cloud provider needs that capacity back, they issue an **Interruption Warning** to the node instance.

| Cloud Provider | Interruption Warning Time | Notification Protocol |
|---|---|---|
| **AWS** | 2 Minutes | Metadata Service (`/latest/meta-data/spot/termination-time`) or EventBridge |
| **Azure** | 30 Seconds | Scheduled Events API (`http://169.254.169.254/metadata/scheduledevents`) |
| **GCP** | 30 Seconds | Metadata Server (`/computeMetadata/v1/instance/preempted`) |

Once the warning is triggered, a countdown begins. If no action is taken, the VM is abruptly terminated, leading to dirty database states, interrupted client connections, and pod scheduling failures.

---

## 2. Cluster-Level Interruption Handlers

In modern clusters, we deploy controllers that poll the cloud metadata service or subscribe to termination events.

### native Karpenter Interruption Handling
If you use Karpenter, it automatically monitors AWS EventBridge for spot interruption notices. When it receives a warning:
1. It immediately **cordons** the affected spot node (marks it as unschedulable).
2. It begins **draining** the node, evicting the pods.
3. It pre-emptively **provisions** replacement nodes so pods can reschedule without waiting.

To enable this in Karpenter, set the following in your Karpenter Helm controller configuration values:
```yaml
# Helm values for karpenter controller
controller:
  aws:
    interruptionQueueName: KarpenterInterruptionQueue # Requires creating an SQS queue and EventBridge rule
```

---

## 3. Application-Level Graceful Shutdown (The 12-Factor App Pattern)

When Kubernetes drains a node, it sends a `SIGTERM` signal to the containers. If the application does not shut down immediately or ignores the signal, Kubernetes waits for the `terminationGracePeriodSeconds` (default: 30s) and then sends a `SIGKILL` (abrupt kill).

### Handling SIGTERM in Application Code (Node.js Example)
Ensure your app catches the signal, stops accepting new traffic, finishes current requests, and exits cleanly:

```javascript
const express = require('express');
const app = express();
const server = app.listen(8080);

let isShuttingDown = false;

// Health check endpoint
app.get('/healthz', (req, res) => {
  if (isShuttingDown) {
    res.status(503).send('Service is shutting down');
  } else {
    res.status(200).send('OK');
  }
});

// Capture termination signals
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received. Commencing graceful shutdown...');
  isShuttingDown = true;
  
  // Stop accepting new connections at the load balancer level
  server.close(() => {
    console.log('Active network connections closed. Exiting process.');
    process.exit(0);
  });
  
  // Enforce a hard timeout if server close hangs
  setTimeout(() => {
    console.error('Graceful shutdown timeout exceeded. Forcing exit.');
    process.exit(1);
  }, 25000); // Wait up to 25 seconds (must be less than Pod terminationGracePeriod)
});
```

---

## 4. Best Practices Checklist for Spot Workloads

- [ ] **State Isolation**: Never run stateful apps (databases, active file-writes) on spot nodes.
- [ ] **Pod Disruption Budgets (PDBs)**: Ensure at least one replica is always healthy elsewhere (e.g., `minAvailable: 1` or `maxUnavailable: 1`).
- [ ] **Increase terminationGracePeriodSeconds**: Set `terminationGracePeriodSeconds: 60` or `90` for workloads that take time to flush buffers (e.g., sidecars or processing queues).
- [ ] **Workload Spread Constraints**: Use `topologySpreadConstraints` to ensure replicas of a microservice are distributed across multiple nodes and zones. If one spot node goes down, it only affects a fraction of your replicas.
- [ ] **Multi-Instance Type Diversification**: Do not request a single VM size (e.g., only `m5.large`). Tell Karpenter or your ASG to pull from a large pool (e.g., `m5.large`, `m5d.large`, `t3.large`, `c5.large`) to bypass spot pool exhaustion in a single zone.
```yaml
      requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot"]
      - key: node.kubernetes.io/instance-type
        operator: In
        values: ["m5.large", "m5d.large", "c5.large", "c5d.large", "t3.large"]
```
