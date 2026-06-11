# 🚨 GitOps and CI/CD Troubleshooting Playbook
### 🏷️ SRE RUNBOOK FOR PRODUCTION DEPLOYMENTS

When operating GitOps systems, errors occur at the intersection of Git, the GitOps controller, and the Kubernetes API server. This playbook documents 10 common production failure modes, providing symptoms, root causes, commands to investigate, and resolution steps.

---

## 🧭 General Triage Commands

For quick status checks, use these commands:

```bash
# Get ArgoCD Application details and errors
kubectl get applications -n argocd -o yaml

# Stream ArgoCD controller logs for errors
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100 -f

# Get Flux reconciliation failures
flux get kustomizations
flux get helmreleases -A

# Check Flux controller logs
kubectl logs -n flux-system -l app=kustomize-controller --tail=100 -f
```

---

## 🚨 Scenario 1: Immutable Field Sync Failure (ArgoCD)

### Symptoms:
ArgoCD application sync is stuck. The status shows `SharedResourceConflict` or `ValidationError` indicating that it cannot apply a specific manifest field.

### Root Cause:
You attempted to change an **immutable** field on a running Kubernetes resource (e.g., changing the `spec.selector` of a Deployment, or the `spec.clusterIP` of a Service). Kubernetes does not allow these fields to be updated in-place.

### Investigation:
```bash
# Check the application status condition block
kubectl get application <app-name> -n argocd -o jsonpath="{.status.conditions}"
```
*Look for: `Service "my-service" is invalid: spec.clusterIP: Invalid value: ... field is immutable`.*

### Resolution:
1. **Re-create option:** If acceptable in dev/staging, run a manual delete on the target resource, then let ArgoCD auto-recreate it:
   ```bash
   kubectl delete service my-service -n dev-env
   ```
2. **Force-Sync option (Production):** In ArgoCD UI, trigger Sync with `Replace` option checked, or annotate the manifest in Git with the sync-option replacement tag:
   ```yaml
   metadata:
     annotations:
       argocd.argoproj.io/sync-options: Replace=true
   ```

---

## 🚨 Scenario 2: Flux SOPS Decryption Error

### Symptoms:
Flux `Kustomization` shows a state of `Ready: False` with message: `SOPS decryption failed`.

### Root Cause:
The Kustomize Controller cannot decrypt a secret file because it lacks the required decryption key (AWS KMS role, GCP service account, GCP KMS key permissions, or PGP private key in cluster).

### Investigation:
```bash
# Describe the kustomization to view error events
kubectl describe kustomization <kustomization-name> -n flux-system
```
*Look for: `failed to decrypt file: ... decryption failed: no keys could decrypt the data`.*

### Resolution:
1. Ensure the decryption secret containing the PGP/KMS key exists in the `flux-system` namespace.
2. Verify that the Flux Kustomization manifest references the decryption provider correctly:
   ```yaml
   spec:
     decryption:
       provider: sops
       secretRef:
         name: sops-gpg-key # Must exist in flux-system namespace
   ```

---

## 🚨 Scenario 3: Git SSH Authentication Failure

### Symptoms:
Controllers fail to poll the repository. Applications show `ComparisonError` (ArgoCD) or `GitRepository` shows `AuthenticationFailed` (Flux).

### Root Cause:
The Git deploy key, Personal Access Token (PAT), or SSH credentials stored in the Kubernetes secret have expired, been revoked, or lack repo read access.

### Investigation:
```bash
# For Flux: check GitRepository status
kubectl describe gitrepository <repo-name> -n flux-system

# For ArgoCD: check repository connection status
argocd repo list
```

### Resolution:
1. Generate a new Personal Access Token with repository read scopes.
2. Update the Kubernetes secret:
   ```bash
   # Recreate secret with valid credentials
   kubectl create secret generic git-creds \
     --namespace=argocd \
     --from-literal=password=$NEW_GIT_TOKEN \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

---

## 🚨 Scenario 4: Circular Sync Dependency (Sync Loop)

### Symptoms:
The application sync is in an infinite loop. It continuously alternates between `Synced` and `OutOfSync` every few seconds.

### Root Cause:
A resource in Git is configured to have a field value that is modified dynamically by a controller *in* the cluster (e.g. an autoscaler modifying `replicas`, or a mutating webhook injecting dynamic metadata or default values).

### Investigation:
Run a diff to see what is changing:
```bash
# Inspect the live diff in ArgoCD
argocd app diff <app-name>
```
*Observe if the diff is always on a field like `replicas` (conflict with HPA) or annotations (conflict with mutating webhook like Istio sidecar injector).*

### Resolution:
Exclude the dynamic field from comparison in the application spec:
```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas # Ignore replica changes (delegated to HPA)
```

---

## 🚨 Scenario 5: Stuck Application Finalizers (Namespace deletion fails)

### Symptoms:
You attempt to delete an ArgoCD Application, but it remains stuck in `Terminating` status indefinitely.

### Root Cause:
ArgoCD uses finalizers to ensure resources are cleanly deleted. If the cluster is unreachable or target resources cannot be deleted due to finalizer blocks on *them*, ArgoCD gets stuck.

### Investigation:
```bash
kubectl get application <app-name> -n argocd -o jsonpath="{.metadata.finalizers}"
```

### Resolution:
If you need to force deletion of the Application metadata (ignoring cluster cleanups):
```bash
# Patch the application resource to remove finalizers
kubectl patch app <app-name> -n argocd -p '{"metadata":{"finalizers":null}}' --type=merge
```

---

## 🚨 Scenario 6: Target Namespace Creation Blocked by OPA / Kyverno

### Symptoms:
ArgoCD Application sync fails. The status shows `CreateNamespaceFailed` or `Forbidden`.

### Root Cause:
The GitOps agent attempted to auto-create the target namespace, but the creation request was rejected by a Policy Engine (OPA Gatekeeper or Kyverno) because the namespace lacked mandatory labels (like `owner` or `environment`).

### Investigation:
```bash
kubectl get events -n argocd --sort-by='.metadata.creationTimestamp'
```
*Look for: `admission webhook "validation.gatekeeper.sh" denied the request: namespace requires labels: owner`.*

### Resolution:
Disable ArgoCD namespace auto-creation in `syncOptions` and define the namespace manually in your Git repository manifests with the appropriate labels included:
```yaml
# Add this manifest to Git:
apiVersion: v1
kind: Namespace
metadata:
  name: payment-prod
  labels:
    owner: payments-team
    environment: production
```

---

## 🚨 Scenario 7: Out-of-Memory (OOM) on ArgoCD Repo Server

### Symptoms:
Syncing large applications (especially heavy Helm charts or large monorepos) times out. The Web UI shows `Repo server connection timed out` or `504 Gateway Timeout`.

### Root Cause:
The `argocd-repo-server` pod has reached its memory/CPU limits and was killed by the Kubernetes OOM Killer.

### Investigation:
```bash
# Check if the repo server was restarted due to OOM
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server
kubectl describe pod -n argocd -l app.kubernetes.io/name=argocd-repo-server
```
*Look for: `Last State: Terminated`, `Reason: OOMKilled`.*

### Resolution:
1. Increase resources limits on `argocd-repo-server` deployment:
   ```yaml
   resources:
     limits:
       memory: "2Gi" # Scale up from default
       cpu: "1000m"
   ```
2. Enable Git manifest caching using a larger Redis deployment.

---

## 🚨 Scenario 8: Release Promotion PR Blocked (Invalid Manifests)

### Symptoms:
The promotion pipeline fails during the PR validation phase (e.g. before merging to production).

### Root Cause:
The manifests submitted in the PR contain syntax errors, missing fields, or invalid Kubernetes schemas.

### Investigation:
Verify the error inside the CI pipeline runner logs. Alternatively, test the build output locally:
```bash
# Validate yaml syntax
kustomize build overlays/production | kubectl apply --dry-run=client -f -
```

### Resolution:
Fix the schema validation issues locally, commit the fixes, and push to update the PR.

---

## 🚨 Scenario 9: HelmRelease Upgrade Stuck in "Pending-Upgrade"

### Symptoms:
Flux `HelmRelease` shows status `Ready: False` with message: `Helm upgrade failed: another operation (install/upgrade/rollback) is in progress`.

### Root Cause:
A previous upgrade was interrupted (e.g., node was rescheduled, network disconnected), leaving the Helm release state locked in the cluster secrets storage.

### Investigation:
```bash
# List helm releases in namespace
helm list -n dev-env
```

### Resolution:
Instruct Flux to rollback or reset the release state:
1. Suspend and resume the HelmRelease to trigger an automatic reset:
   ```bash
   flux suspend hr payment-gateway
   flux resume hr payment-gateway
   ```
2. If it remains stuck, manually delete the lock secret (which matches the highest Helm release version number):
   ```bash
   kubectl delete secret -n dev-env -l name=payment-gateway,status=pending-upgrade
   ```

---

## 🚨 Scenario 10: Multi-Cluster Sync Delay (Replication Lag)

### Symptoms:
You merge a commit to Git. Target Cluster A updates instantly, but Target Cluster B (located in a different cloud provider region) remains out-of-date for 15+ minutes.

### Root Cause:
The connection between the GitOps hub cluster (where ArgoCD runs) and the target cluster API is experiencing high latency, or the target cluster webhook endpoints are blocked by firewall rules.

### Investigation:
Compare reconciliation timestamps on both applications:
```bash
kubectl get application -n argocd -o custom-columns=NAME:.metadata.name,SYNCED:.status.reconciledAt
```

### Resolution:
1. **Configure Webhooks:** Rather than relying on ArgoCD's 3-minute polling loop, configure Git provider webhooks to notify the ArgoCD API Server immediately on push.
2. **Deploy Local Agents:** If cluster connections are unstable, migrate from a centralized ArgoCD configuration to decentralized Flux agents running *within* each target cluster.
