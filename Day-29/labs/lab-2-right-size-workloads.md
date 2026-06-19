# Lab 2: Right-Sizing Workloads

In this lab, you will configure a Vertical Pod Autoscaler (VPA) in recommendation mode to automatically analyze pod behavior and calculate the correct CPU and memory requests.

---

## 1. Deploy the Target Workload
Apply a deployment that runs a simple container:

```yaml
# deploy-target.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
  template:
    metadata:
      labels:
        app: api-gateway
    spec:
      containers:
      - name: api-gateway
        image: nginx:alpine
        resources:
          requests:
            cpu: "1"
            memory: 1Gi
          limits:
            cpu: "2"
            memory: 2Gi
```

Deploy the app:
```bash
kubectl apply -f deploy-target.yaml
```

---

## 2. Deploy the VPA Object
Create and apply a VPA resource targetting the deployment. Notice we set `updateMode: "Off"` to prevent the VPA from restarting our pods in production.

```bash
kubectl apply -f ../manifests/hpa-vpa-autoscaler.yaml
```

Verify that the VPA is registered:
```bash
kubectl get vpa api-gateway-vpa
```

---

## 3. Simulate Traffic to Generate Recommendations
VPA needs active metrics to form recommendations. If your cluster is idle, we can trigger simulated load using a curl loop or load generator:

```bash
# Run inside a temporary pod
kubectl run load-generator --image=busybox --restart=Never -- \
  sh -c "while true; do wget -q -O- http://api-gateway.default.svc.cluster.local; sleep 0.1; done"
```

Let it run for 2-3 minutes.

---

## 4. Retrieve VPA Recommendations
Query the VPA resource status to view recommended resource settings:

```bash
kubectl get vpa api-gateway-vpa -o yaml
```

### Expected Output Structure:
```yaml
status:
  recommendation:
    containerRecommendations:
    - containerName: api-gateway
      lowerBound:
        cpu: 100m
        memory: 128Mi
      target:
        cpu: 250m
        memory: 256Mi
      uncappedTarget:
        cpu: 250m
        memory: 256Mi
      upperBound:
        cpu: 500m
        memory: 512Mi
```

### Explanation of Terms:
*   **target**: The recommended resource request. This is the value you should set.
*   **lowerBound**: The minimum requests recommended. If you go below this, you risk performance degradation.
*   **upperBound**: The maximum requests recommended, representing peak usage plus buffers.

---

## 5. Apply the Recommendations (GitOps Action)
To apply the right-sized resource values, update the resource block of your deployment:

```yaml
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
```

Apply the right-sized manifest to the cluster:
```bash
kubectl apply -f deploy-target.yaml
```

Notice how our CPU requests dropped from **1.0 Core to 250m** (75% savings) and Memory requests dropped from **1Gi to 256Mi** (75% savings).

---

## 6. Clean up Lab
```bash
kubectl delete deployment api-gateway
kubectl delete vpa api-gateway-vpa
kubectl delete pod load-generator
```
