# 🧠 Exercise 1: Hardening the ArgoCD Sync Policy

## 🎯 Objective
Configure an ArgoCD `Application` that recovers from cluster anomalies immediately. You will write a sync policy that blocks manual drift, deletes orphaned resources, and uses exponential backoff policies to handle rate limits during failures.

---

## 🛠️ The Challenge

You are given a skeleton ArgoCD Application manifest. Your task is to update the file to meet these platform-engineering requirements:

1. **Auto-Reconciliation:** The Application must sync automatically whenever a commit lands in Git.
2. **Self-Healing:** If someone modifies a live resource (e.g. scales replicas manually), ArgoCD must revert the change within 10 seconds.
3. **Orphan Pruning:** If a resource is deleted from Git, ArgoCD must delete the resource from the Kubernetes cluster.
4. **Namespace Auto-Creation:** If the target namespace doesn't exist, ArgoCD must create it.
5. **Robust Retry Logic:** If a deployment fails due to a temporary resource quota block, ArgoCD must retry up to **8 times**, starting with a backoff duration of **10 seconds**, scaling by a factor of **2**, up to a maximum duration of **5 minutes**.

---

## 📝 Starter Manifest (`app-exercise.yaml`)

Edit this structure to solve the challenge:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: order-service-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/userhimanshuverma/30-Days-of-Production-Kubernetes.git'
    targetRevision: main
    path: Day-20/manifests
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: orders-prod
  syncPolicy:
    # TODO: Implement automated sync, self-healing, pruning, namespace creation, and retry logic.
```

---

## 🏆 Evaluation Checklist

To verify your solution:
1. Apply the hardened application to your cluster.
2. Verify that the target namespace `orders-prod` was created automatically.
3. Run `kubectl scale deployment/payment-service --replicas=8 -n orders-prod` and verify that ArgoCD automatically scales it back down to its Git value.
4. Run `kubectl describe application order-service-app -n argocd` and check if the retry backoff policies match the rules.
