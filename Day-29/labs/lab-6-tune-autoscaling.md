# Lab 6: Tune Autoscaling Behavior

In this lab, you will configure a Horizontal Pod Autoscaler (HPA) with advanced scaling policies, simulating traffic spikes and validating that the cooldown configurations prevent scaling thrashing.

---

## 1. Deploy the Target Application

Create a deployment that will scale dynamically:

```yaml
# autoscale-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing-service-optimized
spec:
  replicas: 2
  selector:
    matchLabels:
      app: billing-service-optimized
  template:
    metadata:
      labels:
        app: billing-service-optimized
    spec:
      containers:
      - name: billing
        image: nginx:alpine
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: billing-service-optimized
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: billing-service-optimized
```

Apply:
```bash
kubectl apply -f autoscale-app.yaml
```

---

## 2. Apply Custom HPA Behavior Rules

Deploy the HPA manifest we configured earlier in manifests directory:

```bash
kubectl apply -f ../manifests/hpa-vpa-autoscaler.yaml
```

This HPA has:
*   `stabilizationWindowSeconds: 0` for **scaleUp** (scale up immediately).
*   `stabilizationWindowSeconds: 300` for **scaleDown** (hold peak capacity for 5 minutes before terminating pods).

Verify the HPA has registered:
```bash
kubectl get hpa billing-hpa
```

---

## 3. Simulate a Traffic Spike
Launch a heavy load simulation to trigger a scale-up:

```bash
# Start an aggressive load generator running 10 parallel threads
kubectl run load-generator --image=busybox --restart=Never -- \
  sh -c "while true; do wget -q -O- http://billing-service-optimized.default.svc.cluster.local; done"
```

Watch the HPA and replicas scale up in real time:
```bash
kubectl get hpa billing-hpa -w
```

### Expected Output (Scale-Up phase):
Within 15–30 seconds, HPA detects the CPU spikes and triggers a scale-up:
```
NAME          REFERENCE                              TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
billing-hpa   Deployment/billing-service-optimized   92%/75%    2         15        2          2m
billing-hpa   Deployment/billing-service-optimized   120%/75%   2         15        4          2m15s
billing-hpa   Deployment/billing-service-optimized   74%/75%    2         15        8          2m30s
```
*Notice how rapidly it scaled from 2 to 8 replicas (stabilization window: 0s).*

---

## 4. Stop Traffic and Observe the Cooldown Window
Delete the load generator to stop the load:

```bash
kubectl delete pod load-generator
```

Continue watching the HPA output:
```bash
kubectl get hpa billing-hpa -w
```

### Expected Output (Scale-Down phase):
*   At `0m` after stopping load: CPU usage falls to `0%`.
*   At `1m` after stopping load: Replicas remain at `8`.
*   At `3m` after stopping load: Replicas remain at `8`.
*   At `5m` after stopping load (300 seconds): The stabilization window closes. The HPA controller begins scaling down slowly, terminating 10% of replicas per minute.

```
billing-hpa   Deployment/billing-service-optimized   0%/75%   2         15        8          7m
billing-hpa   Deployment/billing-service-optimized   0%/75%   2         15        7          8m
```

This prevents the cluster from deleting pods only to immediately provision them again if traffic returns.

---

## 5. Clean up Lab
```bash
kubectl delete -f autoscale-app.yaml
kubectl delete hpa billing-hpa
```
