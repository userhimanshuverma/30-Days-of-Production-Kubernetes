# ⚡ Production Operator Patterns & Lessons Learned at Scale

Running custom Operators and CRDs in massive production environments (hundreds of nodes, thousands of custom resources) introduces unique platform bottlenecks. Below are senior-level engineering patterns, lessons learned, and failure recovery playbooks.

---

## 1. Reconciliation Best Practices & Pitfalls

### Ensure Absolute Idempotence
The reconciliation loop (`Reconcile()`) is invoked continuously. It must be written such that running it a thousand times yields the same result as running it once.
- **Rule:** Never assume an action will complete immediately.
- **Bad Pattern:** Calling `CreatePod()` and expecting it to be there in the next line of code. The API Server takes time to serialize, mutate, validate, and write resources to etcd.
- **Correct Pattern:** Check if the resource already exists in the **Local Lister Cache** first. If not found in cache, execute creation. If found, compare specs and update if drifted.

### Avoid Infinite Loops (Self-Triggering)
A classic operator bug: the reconciler modifies the spec of the object it is watching.
- **The Bug:** If you update the resource's spec inside `Reconcile()`, the API Server generates an `UPDATE` event. The informer catches this event, enqueues the key, and triggers the reconciler again, causing an infinite loop.
- **The Fix:** Only modify the `/status` subresource during a standard run, not the spec. Configure your controllers with **Generation Change Predicates** so they ignore updates that only affect the resource's metadata status or metadata annotations.

```go
// Kubebuilder / controller-runtime predicate filter
func (r *PostgresReconciler) SetupWithManager(mgr ctrl.Manager) error {
    return ctrl.NewControllerManagedBy(mgr).
        For(&databasev1alpha1.PostgresCluster{}, builder.WithPredicates(predicate.GenerationChangedPredicate{})).
        Complete(r)
}
```

---

## 2. Controller Performance Optimization

### Cache Warming & Memory Management
Shared Informers maintain a complete cache of all watched resources.
- **Memory Bloat:** If your operator watches core resources like `Secrets` or `ConfigMaps` cluster-wide, it will pull every Secret in the cluster into its local RAM cache, causing memory exhaustion (OOMKilled).
- **The Fix:** Use **Metadata-Only Watches** or **Selectors**. Configure the operator manager's cache to only cache secrets that contain specific labels (e.g., `app.kubernetes.io/managed-by: postgres-operator`).

### Concurrency and Rate Limiting
By default, controllers process events using a single worker thread. For large clusters, this causes a backed-up workqueue (reconciliation lag).
- **The Fix:** Increase concurrency in the controller configuration.
- **Rate Limiting:** Use token bucket rate limiting on the workqueue (`MaxOfRateLimiter` combining exponential backoff and bucket rate limiters) to prevent a failing resource from starving the operator's execution threads.

```go
// Example increasing concurrency to 10 workers in controller-runtime
opts := controller.Options{MaxConcurrentReconciles: 10}
```

---

## 3. Webhooks & API Versioning

### Validation & Mutation Admission Webhooks
Relying entirely on OpenAPI schemas in CRDs is insufficient for complex business logic (e.g., verifying that storage configurations cannot be shrunken since most PVs don't support shrinking).
- **Mutating Admission Webhooks:** Automatically inject default values, system sidecars, and organizational labels.
- **Validating Admission Webhooks:** Block actions that violate system logic.
- **Failure Policy Warning:** When configuring webhooks, you must decide between `FailurePolicy: Fail` (default) or `FailurePolicy: Ignore`.
  - If set to `Fail`, and your operator controller deployment crashes, **all pod deployment API calls will block and fail**, freezing cluster actions. Always run webhooks with multiple replicas and configure appropriate namespace exclusions.

### API Version Upgrades (Conversion Webhooks)
When moving from `v1alpha1` to `v1beta1` or `v1`, you must support old API clients.
- If schema fields changed name, you must deploy a **Conversion Webhook**.
- The API Server queries the conversion webhook on-the-fly to translate resources from one schema version to another before persisting or returning them.

---

## 4. Troubleshooting Production Incidents

### The Stuck Finalizer Deadlock
- **Symptom:** You execute `kubectl delete postgrescluster prod-db` and the command blocks indefinitely.
- **Root Cause:** Custom resources use **Finalizers** (e.g., `finalizer.database.production.k8s/cleanup`) to ensure the operator cleans up physical storage volumes, external load balancers, or DNS records before the metadata object is deleted. If the operator crashes or lacks RBAC permissions to clean up resources, the resource remains stuck in a `Terminating` state.
- **Investigation:** Check metadata for `deletionTimestamp` and `finalizers` blocks.
- **Emergency Mitigation:** If you want to force deletion and manually clean up, strip the finalizers block via a patch:
  ```bash
  kubectl patch postgrescluster prod-db --type json --patch='[{"op": "remove", "path": "/metadata/finalizers"}]'
  ```

### Cache Drift & Stale Reads
- **Symptom:** The operator creates a service, but immediately afterward creates it again, throwing `AlreadyExists` errors.
- **Root Cause:** Stale Lister Cache. The operator updated etcd, but the Informer watch event has not yet traveled back to update the local cache store. When the reconciler runs, it reads the stale cache (which shows the service is missing) and tries to recreate it.
- **The Fix:** Handle `AlreadyExists` errors gracefully inside the reconciler by adopting or updating the existing object rather than crashing.

---

## 5. Architectural Scale Decisions: Scope Limits

When designing your operator, carefully analyze its deployment scope:
1. **Namespace-Scoped (Watched Namespaces):** The operator watches only its local namespace or a designated list. Safer, limits RBAC exposure, but requires deploying one operator instance per team namespace.
2. **Cluster-Scoped (Cluster-Wide):** Watches all namespaces in the cluster. Highly efficient, but requires cluster-wide admin privileges and poses a single point of failure (SPOF) risk for the entire control plane.
