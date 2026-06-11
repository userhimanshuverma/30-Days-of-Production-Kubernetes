# 🧪 Lab 5: Declarative Helm Deployments via GitOps

In production, many services (databases, monitoring agents, ingresses) are packaged as Helm charts. GitOps lets us deploy these charts declaratively, removing the need for SREs to run `helm install` from their laptops.

In this lab, we will deploy a Helm release using Flux v2's Helm controller.

---

## 💡 The Two Approaches: ArgoCD vs. Flux

Before we start, note the difference in how these tools handle Helm:
* **ArgoCD (Render & Apply):** The repo server runs `helm template` to render the chart into plain YAML manifests, caches them, and the controller applies them to the cluster. ArgoCD doesn't use the Helm storage backend (so `helm list` inside the cluster won't show anything).
* **Flux (Helm Native):** Flux runs a dedicated `HelmController`. It retrieves charts and runs actual Helm actions (`helm install/upgrade/test`) using the Helm SDK. Flux tracks releases natively (so `helm list` inside the cluster *will* show the release).

---

## Step 1: Deploy the Helm Manifests
We will deploy the `HelmRepository` and `HelmRelease` configurations we created in the `flux/` directory:

```bash
kubectl apply -f ../flux/flux-helmrelease.yaml
```

This resource creates:
1. A `HelmRepository` resource telling Flux to index the Bitnami registry.
2. A `HelmRelease` resource instructing Flux to deploy version `15.x.x` of the `nginx` chart as `payment-gateway` in the `dev-env` namespace.

---

## Step 2: Track Helm Download and Release Sync

### 1. Verify Helm Repository index:
```bash
flux get sources helm
```
**Expected Output:**
```text
NAME            URL                                    REVISION   SUSPENDED   READY   MESSAGE
bitnami-charts  https://charts.bitnami.com/bitnami     ...        false       True    stored artifact for revision '...'
```

### 2. Verify Helm Release installation:
```bash
flux get helmreleases
```
**Expected Output:**
```text
NAME              REVISION   SUSPENDED   READY   MESSAGE
payment-gateway   15.4.3     false       True    Release reconciliation succeeded
```

If the status is `True`, Flux has successfully deployed the Helm chart!

---

## Step 3: Verify Deployed Resources in Cluster
Check that the pods and services configured inside the Helm chart are running:

```bash
kubectl get all -n dev-env -l app.kubernetes.io/name=nginx
```

**Expected Output:**
```text
NAME                                   READY   STATUS    RESTARTS   AGE
pod/payment-gateway-6d8b9d5c4b-abcde   1/1     Running   0          2m
pod/payment-gateway-6d8b9d5c4b-fghij   1/1     Running   0          2m
pod/payment-gateway-6d8b9d5c4b-xxxxx   1/1     Running   0          2m

NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/payment-gateway   ClusterIP   10.96.220.10    <none>        80/TCP    2m
```
*Note: The Helm chart spawned 3 replica pods because we configured `replicaCount: 3` in the values block of our `flux-helmrelease.yaml` manifest.*

---

## Step 4: Declarative Upgrade (Modifying Values)
To update values or versions in GitOps, **you do not run `helm upgrade`**. You modify the manifest in Git.

If you want to scale the deployment down to 1 pod:
1. Open the [flux-helmrelease.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-20/flux/flux-helmrelease.yaml) file.
2. Locate `replicaCount: 3` under the `values` block.
3. Change it to `replicaCount: 1`.
4. Apply the updated manifest to simulate a Git sync:
   ```bash
   kubectl apply -f ../flux/flux-helmrelease.yaml
   ```
5. Force Flux to reconcile:
   ```bash
   flux reconcile helmrelease payment-gateway
   ```
6. Check replicas inside the cluster:
   ```bash
   kubectl get pods -n dev-env -l app.kubernetes.io/name=nginx
   ```
   *You will see two pods terminating, leaving exactly 1 running.*
