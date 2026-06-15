# 🚨 Troubleshooting Operators & Custom Resources Runbook

This playbook provides actionable incident response steps for common failures involving Custom Resource Definitions (CRDs), Custom Controllers, and the Operator Framework in production clusters.

---

## Incident 1: Custom Resource Blocked in "Terminating" State

### Symptoms
Deleting a Custom Resource (e.g., `kubectl delete postgrescluster prod-db`) hangs indefinitely. Pods might be gone, but the parent metadata object refuses to clear.

### Root Cause
The resource spec includes a `metadata.finalizers` string. Kubernetes API prevents metadata deletion if finalizers are present. The managing Operator is responsible for performing cleanup and removing the finalizer string. If the Operator has crashed, is uninstalled, or lacks RBAC permissions to clean up resources, the deletion hangs.

### Investigation
Inspect the object metadata for stuck finalizers and deletion timestamps:
```bash
kubectl get postgrescluster prod-db -o yaml
```
Look for:
```yaml
metadata:
  deletionTimestamp: "2026-06-15T14:22:33Z"
  finalizers:
  - finalizer.database.production.k8s/cleanup
```
Verify if the operator controller pod is running and inspect its logs for deletion failures:
```bash
kubectl logs deployment/postgres-operator -c operator | grep -i finalizer
```

### Resolution
1. **Normal Recovery:** Troubleshoot and fix the operator deployment (e.g., correct RBAC permissions or restart crash-looping pod). The operator will run, clean up the child workloads, strip the finalizer, and the resource will delete.
2. **Forced Cleanup (Emergency Only):** If the operator is decommissioned and you need to manually clean up etcd metadata:
   ```bash
   kubectl patch postgrescluster prod-db --type json --patch='[{"op": "remove", "path": "/metadata/finalizers"}]'
   ```

---

## Incident 2: Operator CrashLoopBackOff: "Forbidden" API Calls

### Symptoms
The operator controller pod crashes repeatedly with log lines showing HTTP `403 Forbidden` API exceptions.

### Root Cause
The `ServiceAccount` assigned to the operator deployment does not possess the correct `ClusterRole` or `Role` bindings. When the controller attempts to create a Shared Informer watch on the custom resources, or attempts to provision Pods/StatefulSets, the API Server denies access.

### Investigation
Check the container logs:
```bash
kubectl logs deployment/postgres-operator -c operator
```
Look for errors resembling:
```text
Failed to watch *v1.StatefulSet: failed to list *v1.StatefulSet: statefulsets.apps is forbidden: 
User "system:serviceaccount:default:postgres-operator-sa" cannot list resource "statefulsets" in API group "apps"
```

### Resolution
Update the RBAC configuration. Ensure that the `ClusterRole` permissions match all target resources managed by the reconciler logic. Inspect [operator-rbac-deployment.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-24/manifests/operator-rbac-deployment.yaml) for correct mappings:
```bash
kubectl apply -f manifests/operator-rbac-deployment.yaml
```
Verify the service account is associated with the deployment pod spec:
```bash
kubectl get deployment postgres-operator -o yaml | grep serviceAccountName
```

---

## Incident 3: Infinite Reconciliation Loops (Self-Triggering)

### Symptoms
The operator pod consumes high CPU. Logs are flooded with continuous, repeating reconciliation statements for the same resource keys within milliseconds, even though no configurations have changed.

### Root Cause
The controller's `Reconcile()` method is updating the custom resource's **spec** fields (or metadata parameters that trigger informer watch changes) rather than updating only the `/status` subresource. This causes the controller to react to its own updates, creating an infinite loop.

### Investigation
Examine the write events:
```bash
kubectl get events -n default --sort-by='.metadata.creationTimestamp'
```
Watch the resource metadata generation number:
```bash
kubectl get postgrescluster prod-db -w -o jsonpath='{.metadata.generation}'
```
*Observation:* If the metadata generation number increments on every loop, the controller is writing to the spec.

### Resolution
1. Refactor the operator code to ensure it only updates `/status` subresources using `UpdateStatus()` APIs.
2. Verify that the CRD defines `status: {}` subresource block.
3. Configure informer predicates (e.g., `GenerationChangedPredicate`) to filter out metadata and status update triggers.

---

## Incident 4: CRD Spec Apply Fails: "Metadata.Name is Invalid"

### Symptoms
Running `kubectl apply -f postgres-crd.yaml` yields:
```text
The CustomResourceDefinition "postgresclusters" is invalid: metadata.name: Invalid value: "postgresclusters":
must be: <plural>.<group>
```

### Root Cause
A CRD's `metadata.name` is not arbitrary. It must exactly match the naming convention `<plural>.<group>`. If the group is `database.production.k8s` and plural is `postgresclusters`, the metadata name must be `postgresclusters.database.production.k8s`.

### Investigation
Verify the CRD spec configuration:
```yaml
metadata:
  name: postgresclusters           # ERROR: Missing group suffix
spec:
  group: database.production.k8s
  names:
    plural: postgresclusters
```

### Resolution
Correct the `metadata.name` field to match the naming convention:
```yaml
metadata:
  name: postgresclusters.database.production.k8s
```
Apply the manifest again.

---

## Incident 5: Validating Webhook Denies All Resource Submissions (Fail Closed)

### Symptoms
No one can deploy pods, deployments, or custom resources. Every apply command errors with timeouts or connection refusals.

### Root Cause
A Validating Admission Webhook was configured with `FailurePolicy: Fail` (fail closed). The webhook server container in the operator deployment crashed or is unreachable, causing the `kube-apiserver` to block all incoming write requests.

### Investigation
Identify active validating webhooks:
```bash
kubectl get validatingwebhookconfigurations
```
Describe the configuration to check the endpoints and failure policies:
```bash
kubectl describe validatingwebhookconfiguration postgres-operator-webhook
```

### Resolution
1. **Temporary Emergency Restore:** If the cluster operations are entirely paralyzed and the operator is down, delete the webhook configuration to stop API checks:
   ```bash
   kubectl delete validatingwebhookconfiguration postgres-operator-webhook
   ```
2. **Long-Term Protection:** Fix the operator pod health, ensure webhook services are scaled, and set the policy to `FailurePolicy: Ignore` if the validation is non-critical for core cluster health.
