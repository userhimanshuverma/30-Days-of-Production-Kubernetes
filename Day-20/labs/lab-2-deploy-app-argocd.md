# 🧪 Lab 2: Deploying Applications via ArgoCD

In this lab, we will configure an ArgoCD project boundary (`AppProject`) and deploy our first microservice using an ArgoCD `Application` resource.

---

## Step 1: Create the AppProject
The `AppProject` acts as a security sandbox. Apply the project manifest:

```bash
kubectl apply -f ../argocd/argocd-appproject.yaml
```

Verify it was created successfully:
```bash
kubectl get appproject -n argocd
```
**Expected Output:**
```text
NAME              AGE
default           10m
payment-project   12s
```

---

## Step 2: Deploy the Application Manifest
Now, apply the `Application` manifest. This instructs ArgoCD to watch the repository and deploy the manifests located in the `Day-20/manifests` folder.

```bash
kubectl apply -f ../argocd/argocd-application.yaml
```

---

## Step 3: Monitor Sync and Reconciliation
Since we configured automated sync in `argocd-application.yaml` (`syncPolicy.automated`), ArgoCD will immediately begin to deploy our application resources to the `dev-env` namespace.

Inspect the status using the ArgoCD Web UI dashboard or the CLI:

### Option A: Check via Kubernetes CLI
List the application state directly from Kubernetes:
```bash
kubectl get application -n argocd payment-service-app
```
**Expected Output:**
```text
NAME                  SYNC STATUS   HEALTH STATUS
payment-service-app   Synced        Healthy
```

### Option B: Check details
```bash
kubectl describe application -n argocd payment-service-app
```
Look at the events at the bottom. You should see steps logging the deployment creation, service creation, and namespace sync.

---

## Step 4: Verify the Workload in the Cluster
Ensure the target application resources have been successfully spawned inside the namespace:

```bash
# Check resources in target namespace
kubectl get all -n dev-env
```

**Expected Output:**
```text
NAME                                   READY   STATUS    RESTARTS   AGE
pod/payment-service-5c68f94946-abcde   1/1     Running   0          30s
pod/payment-service-5c68f94946-fghij   1/1     Running   0          30s

NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/payment-service   ClusterIP   10.96.142.180   <none>        80/TCP    30s

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/payment-service   2/2     2            2           30s
```

You have successfully completed a pull-based deployment using ArgoCD!
