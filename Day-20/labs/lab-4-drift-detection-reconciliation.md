# 🧪 Lab 4: Drift Detection & Automated Reconciliation

One of the greatest features of a pull-based GitOps deployment is the ability to automatically detect and correct configuration drift. In this lab, we will manually alter resources in the cluster and watch the GitOps controllers restore order.

---

## Step 1: Simulate Configuration Drift (Manual Scaling)
Let's bypass Git and change the replicas of our `payment-service` directly in the cluster:

```bash
# Scale the deployment manually to 4 replicas
kubectl scale deployment/payment-service --replicas=4 -n dev-env
```

Verify that the cluster scaled up to 4 pods:
```bash
kubectl get pods -n dev-env
```
**Expected Output:**
```text
(4 pods running/starting)
```

---

## Step 2: Observe ArgoCD Drift Handling

If you configured ArgoCD with `selfHeal: true` (which we did in `argocd-application.yaml`), you will notice something interesting. Let's list the pods again immediately:

```bash
kubectl get pods -n dev-env
```
**Expected Output:**
```text
payment-service-5c68f94946-abcde   1/1     Running       0          5m
payment-service-5c68f94946-fghij   1/1     Running       0          5m
payment-service-5c68f94946-xxxxx   1/1     Terminating   0          5s
payment-service-5c68f94946-yyyyy   1/1     Terminating   0          5s
```
**What happened?**
The ArgoCD Application Controller detected that the live cluster state (4 replicas) drifted from the desired state in Git (2 replicas). Because `selfHeal` was active, it immediately issued a patch command to force the cluster back to 2 replicas.

### What if Self-Healing is Disabled?
If we disable self-healing:
1. SRE updates manual replicas to 4.
2. ArgoCD flags the application status as **OutOfSync** in the Web UI.
3. We can view the exact difference using the CLI:
   ```bash
   # (Needs ArgoCD CLI logged in)
   argocd app diff payment-service-app
   ```
   *Output will show a diff indicating that Git expects `replicas: 2` but the live state is `replicas: 4`.*

---

## Step 3: Observe Flux Drift Handling

If you are using Flux:
The `KustomizeController` also periodically compares state (default is 5 minutes as specified by the `interval` field in `flux-kustomization.yaml`).

Let's test Flux drift detection by editing a ConfigMap:

```bash
# Manually update a key inside the cluster configmap
kubectl patch configmap/payment-config -n dev-env -p '{"data":{"LOG_LEVEL":"debug"}}'
```

Verify the live configuration change:
```bash
kubectl get configmap/payment-config -n dev-env -o jsonpath="{.data.LOG_LEVEL}"
# Output: debug
```

Now, force Flux to reconcile immediately to witness the self-healing:
```bash
flux reconcile kustomization payment-service-reconcile --with-source
```

Check the ConfigMap value again:
```bash
kubectl get configmap/payment-config -n dev-env -o jsonpath="{.data.LOG_LEVEL}"
# Output: info
```
**Flux successfully self-healed the ConfigMap!** The manual modification was overwritten because it did not exist in Git.

---

## Step 4: Reviewing Controller Logs

To see the decision logs, check the controller output:

* **For ArgoCD:**
  ```bash
  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
  ```
  *Look for messages containing: `Reconciliation completed`, `spec.replicas: 4 -> 2`, or `Syncing application payment-service-app`.*

* **For Flux:**
  ```bash
  kubectl logs -n flux-system -l app=kustomize-controller --tail=100
  ```
  *Look for messages containing: `Kustomization reconciled`, `ConfigMap/dev-env/payment-config configured`.*
