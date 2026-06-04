# 🛠️ Lab 1: Metrics Server, HPA, & VPA Hands-on Guide

Learn how to install, configure, and inspect metrics pipelines and workload scaling behaviors in a running Kubernetes cluster.

---

## Prerequisites
* A running local cluster: [Kind](https://kind.sigs.k8s.io/) or [Minikube](https://minikube.sigs.k8s.io/).
* `kubectl` CLI installed and configured.

---

## Lab 1: Installing and Verifying Metrics Server

By default, local clusters do not include a Metrics Server. We will install one and configure it to bypass TLS verification for lab testing.

### Step 1: Apply the Manifest
Apply the Metrics Server deployment config:
```bash
kubectl apply -f ../manifests/metrics-server.yaml
```

*Note: This manifest includes the `--kubelet-insecure-tls` flag, allowing metrics aggregation in clusters running self-signed kubelet certificates.*

### Step 2: Verify Installation
Wait for the deployment to become ready:
```bash
kubectl rollout status deployment/metrics-server -n kube-system
```

Check if the Metrics API responds:
```bash
kubectl get apiservice v1beta1.metrics.k8s.io
```
*Expected Output:*
```
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        1m
```

### Step 3: Test Resource Retrieval
Query node and pod metrics:
```bash
kubectl top nodes
kubectl top pods -n kube-system
```
*It may take up to 60 seconds after startup for the metrics server to complete its initial scraping cycle.*

---

## Lab 2: Configure HPA (CPU & Memory Scaling)

We will deploy our sample high-performance API workload and attach an HPA to it.

### Step 1: Deploy the Target Workload
Apply the API Deployment and Service:
```bash
kubectl apply -f ../manifests/api-workload.yaml
```

Wait for the pods to run:
```bash
kubectl get pods -l app=dynamic-api
```

### Step 2: Create the HPA Resource
Apply the HPA configuration which targets CPU and Memory utilization:
```bash
kubectl apply -f ../manifests/hpa-cpu-memory.yaml
```

Check HPA initial status:
```bash
kubectl get hpa dynamic-api-hpa
```
*Expected Output:*
```
NAME              REFERENCE                        TARGETS           MINPODS   MAXPODS   REPLICAS   AGE
dynamic-api-hpa   Deployment/dynamic-api-service   0%/60%, 0%/80%    3         20        3          30s
```

### Step 3: Generate Artificial CPU Load
Deploy a temporary load generator container to send a continuous stream of HTTP requests to the API service:
```bash
kubectl run load-generator --rm -i --tty --image=busybox:1.28 --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://dynamic-api-service; done"
```

### Step 4: Observe HPA Scaling Actions
Open a separate terminal window and monitor the HPA:
```bash
kubectl get hpa dynamic-api-hpa -w
```

Watch the CPU percentage rise and see the replica count scale from `3` up to `6`, `10`, or more as target metrics are exceeded.

You can also view scaling event logs:
```bash
kubectl describe hpa dynamic-api-hpa
```
*Expect to see a `SuccessfulRescale` event in the output.*

### Step 5: Clean Up Load
Terminate the load generator terminal window (Ctrl+C). The HPA will maintain high replica counts for 5 minutes (`stabilizationWindowSeconds: 300` in the scaleDown behavior) before gradually scaling back to the minimum replica count of `3` to protect against scaling oscillations.

---

## Lab 3: Deploy VPA (Recommendation Mode)

Let's test the Vertical Pod Autoscaler's capacity recommendation engine.

*Important: VPA requires installing the VPA custom resource definitions (CRDs) and controllers. If you are running Minikube, enable VPA with:*
```bash
minikube addons enable vpa
```
*If running Kind, you must clone the `kubernetes/autoscaler` repo and run `hack/vpa-up.sh`.*

### Step 1: Apply the VPA Spec
Apply the VPA configured in `RecommendationOnly` mode:
```bash
kubectl apply -f ../manifests/vpa-recommendation.yaml
```

### Step 2: Query Recommendations
Wait a few minutes, then describe the VPA:
```bash
kubectl describe vpa dynamic-api-vpa
```

*Look for the `Status.Recommendation` block in the output:*
```yaml
  Recommendation:
    Container Recommendations:
      Container Name:  web-app
      Lower Bound:
        Cpu:     100m
        Memory:  256Mi
      Target:
        Cpu:     120m
        Memory:  256Mi
      Uncapped Target:
        Cpu:     120m
        Memory:  256Mi
      Upper Bound:
        Cpu:     350m
        Memory:  512Mi
```
*Because `updateMode` is set to `"Off"`, VPA acts as an advisor, reporting optimal container requests/limits without restarting the running pods.*
