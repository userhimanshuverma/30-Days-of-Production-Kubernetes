# 🧪 Lab 3: Bootstrapping and Deploying via Flux v2

In this lab, we will bootstrap a GitOps repository using the Flux CLI and deploy our application using Flux's `GitRepository` and `Kustomization` custom resources.

---

## Step 1: Bootstrapping Flux (Theory & Command)

Bootstrapping installs Flux controllers in your cluster and sets up sync configurations pointing directly back to your GitHub repository.

To run bootstrap in production, you must set your Git credentials. 

```bash
# Export your Git personal access token (PAT)
export GITHUB_TOKEN="ghp_yourpersonalaccesstokenhere"
export GITHUB_USER="your-github-username"

# Run the bootstrap command (replace repository name to match your repo)
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=30-Days-of-Production-Kubernetes \
  --branch=main \
  --path=./clusters/my-cluster \
  --personal
```

*Note: For the purpose of this lab, if you do not want to execute bootstrap on your live repo, you can install the Flux controllers locally in standalone mode:*
```bash
flux install
```

---

## Step 2: Configure Git Source and Kustomization
If you did not use the `bootstrap` command, you must tell Flux where to download manifests. Apply the local configuration manifests we created:

```bash
kubectl apply -f ../flux/flux-kustomization.yaml
```

This resource creates:
1. A `GitRepository` source resource pointing to our code/config repository.
2. A `Kustomization` resource instructions Flux to apply the manifests under `Day-20/manifests` every 5 minutes.

---

## Step 3: Monitor Reconciliation
We can query Flux status directly using the `flux` CLI tool.

### Check Sources
Verify that Flux successfully cloned and packaged the Git repository:

```bash
flux get sources git
```

**Expected Output:**
```text
NAME               REVISION                                          SUSPENDED   READY   MESSAGE
main-config-source main@sha1:e0a12b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s   false       True    stored artifact for revision 'main@sha1:e0a12b3...'
```

### Check Kustomization Status
Verify that Kustomize controller has successfully reconciled the manifests:

```bash
flux get kustomizations
```

**Expected Output:**
```text
NAME                         REVISION                                          SUSPENDED   READY   MESSAGE
payment-service-reconcile    main@sha1:e0a12b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s   false       True    Applied revision: main@sha1:e0a12b3...
```

---

## Step 4: Manually Trigger a Reconcile
By default, Flux polls every few minutes. If you make a commit in Git and want to apply it immediately without waiting, you can force-trigger reconciliation using:

```bash
flux reconcile kustomization payment-service-reconcile --with-source
```

**Expected Output:**
```text
► reconciling Kustomization payment-service-reconcile in flux-system namespace
✔ Kustomization reconciled successfully
▲ Kustomization healthy
```
Your cluster is now actively synced via Flux!
