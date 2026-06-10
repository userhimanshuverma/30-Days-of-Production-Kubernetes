# 🧪 Lab 3: Debug Service Connectivity

## Objective
Learn how to troubleshoot network connectivity failures resulting from selector and port configuration mismatches between a Service and its Backend Pods.

## Broken Environment
We will use the manifest [service-selector-broken.yaml](../manifests/service-selector-broken.yaml) which deploys a backend app and service with mismatched label selectors and port configuration.

---

## Step-by-Step Investigation

### 1. Apply the Broken Manifest
Apply the manifest to the cluster:
```bash
kubectl apply -f ../manifests/service-selector-broken.yaml
```

### 2. Verify Resource Status
Check if the pods and service exist:
```bash
kubectl get pods,svc -l tier=backend
```

**Expected Output:**
```text
NAME                             READY   STATUS    RESTARTS   AGE
pod/order-api-6bbf7589d9-abc12   1/1     Running   0          30s
pod/order-api-6bbf7589d9-def34   1/1     Running   0          30s

NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/order-service   ClusterIP   10.96.142.155   <none>        80/TCP    30s
```

### 3. Check Service Endpoints
Verify if the service has successfully selected any backend pods:
```bash
kubectl get endpoints order-service
```

**Expected Output:**
```text
NAME            ENDPOINTS   AGE
order-service   <none>      45s
```
*Note that ENDPOINTS is empty (`<none>`). The service is not routing traffic to any pods.*

### 4. Diagnose Label Mismatches
Inspect the service selector:
```bash
kubectl get svc order-service -o jsonpath='{.spec.selector}'
```
**Output:** `{"app":"order-api","tier":"backend"}`

Now check the labels on the actual running pods:
```bash
kubectl get pods -l tier=backend --show-labels
```
**Output:**
```text
NAME                         LABELS
order-api-6bbf7589d9-abc12   app=order-api-v1,pod-template-hash=6bbf7589d9,tier=backend
```
The Service is looking for pods with label `app=order-api`, but the pods are tagged with `app=order-api-v1`.

### 5. Diagnose Port Mismatches
Inspect the Service ports configuration:
```bash
kubectl get svc order-service -o yaml | grep -A 5 ports
```
The Service targetPort is pointing to `8080`.
Inspect the pod spec container port configurations:
```bash
kubectl get deployment order-api -o yaml | grep containerPort
```
The containers are listening on port `80`. Even if labels matched, the service would forward traffic to port `8080`, resulting in a connection failure.

---

## Resolution Walkthrough

To resolve both issues, update the Service configuration.

1. Open [service-selector-broken.yaml](../manifests/service-selector-broken.yaml).
2. Modify the Service spec:
   * Change `selector.app` from `order-api` to `order-api-v1`.
   * Change `ports[0].targetPort` from `8080` to `80`.
3. Apply the updated manifest:
   ```bash
   kubectl apply -f ../manifests/service-selector-broken.yaml
   ```
4. Verify endpoints are now active:
   ```bash
   kubectl get endpoints order-service
   ```
   **Expected Output:**
   ```text
   NAME            ENDPOINTS                       AGE
   order-service   10.244.1.2:80,10.244.2.3:80   2m
   ```
   *The Service is now successfully routing traffic to the backend pods.*
