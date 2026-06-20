# ArgoCD Drift Detection & Sync Policy Configuration

This guide details how to configure ArgoCD to detect configuration drift, enforce synchronization policies, and ignore expected runtime changes.

---

## 🔍 Understanding Drift Detection
ArgoCD continuously compares the **live state** of resources inside the Kubernetes cluster against the **target state** defined in the Git repository. If the two states differ (e.g. an engineer manually edits a replica count using `kubectl edit`), ArgoCD flags the application as `OutOfSync`.

---

## ⚙️ Drift Prevention Config Spec

To enforce Git as the single source of truth, apply the following properties under the Application's `syncPolicy` spec:

*   **Self-Heal (`selfHeal: true`)**: When ArgoCD detects drift, it automatically triggers a sync to overwrite the manual cluster changes with the configurations defined in Git.
*   **Prune (`prune: true`)**: Deletes resources inside the cluster that are no longer present in the Git repository.

### Example ArgoCD Application Config
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payment-service
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/company/platform-gitops.git'
    targetRevision: HEAD
    path: apps/payment-service
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: payments
  syncPolicy:
    automated:
      prune: true      # Remove orphaned resources
      selfHeal: true   # Revert manual cluster edits
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true # Optimize sync performance
```

---

## ⚠️ Excluding Runtime Fields (`ignoreDifferences`)
Certain runtime values are generated or mutated dynamically in the cluster (e.g. replicas managed by HPA, mutations from mutating webhooks, or system timestamps). SREs must configure ArgoCD to ignore these fields to prevent continuous sync loops.

### Ignoring HPA Replica Drift
```yaml
spec:
  ignoreDifferences:
    # Ignore replica count modifications done by HPA on the deployment
    - group: apps
      kind: Deployment
      name: payment-service-deployment
      jsonPointers:
        - /spec/replicas
    # Ignore cluster-injected service account secrets
    - group: ""
      kind: ServiceAccount
      jsonPointers:
        - /secrets
```
