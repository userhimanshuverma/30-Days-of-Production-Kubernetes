# Lab 1: Analyze Resource Waste

This lab guides you through deploying a heavily overprovisioned application, measuring its actual resource usage vs requests, and calculating the financial cost of this waste.

---

## 1. Deploy the Wasteful Microservice
First, apply the wasteful deployment configuration provided in the manifests directory:

```bash
kubectl apply -f ../manifests/waste-deployment.yaml
```

Wait for the 10 replicas of the deployment to start running:
```bash
kubectl get pods -l app=legacy-billing-service -o wide
```

---

## 2. Inspect CPU & RAM Allocation
Analyze the total resource requests requested by this workload using the following command:

```bash
kubectl describe deployment legacy-billing-service | grep -A 2 -i "requests"
```

### Expected Output:
```
    Requests:
      cpu:      4
      memory:   8Gi
```

Since we deployed **10 replicas**, this single service is requesting:
*   **Total CPU**: 40 Cores
*   **Total Memory**: 80 GiB RAM

---

## 3. Query Actual Utilization
Verify the actual physical resource consumption using the Kubernetes Metrics Server CLI:

```bash
kubectl top pods -l app=legacy-billing-service
```

### Expected Output:
```
NAME                                      CPU(cores)   MEMORY(bytes)
legacy-billing-service-6d8b9f78fb-2pabc   3m           15Mi
legacy-billing-service-6d8b9f78fb-4lmnp   4m           14Mi
... [truncated for brevity] ...
legacy-billing-service-6d8b9f78fb-zxyw8   3m           16Mi
```

Summing up the actual usage across all 10 pods:
*   **Actual CPU**: ~35m (0.035 Cores)
*   **Actual Memory**: ~150MiB RAM

---

## 4. Calculate Resource Slack & Cost Impact

Let's compute the **Slack (Waste)**:

$$\text{CPU Slack} = 40.0 - 0.035 = 39.965\text{ Cores}$$
$$\text{Memory Slack} = 80.0\text{ GiB} - 0.15\text{ GiB} = 79.85\text{ GiB}$$

### Financial Cost Calculation (AWS standard pricing for m5.2xlarge nodes)
Assume an `m5.2xlarge` node (8 Cores, 32GB RAM) costs **$0.384 / hour** (approx. $0.048 per Core hour, $0.012 per GB hour).

*   **Hourly Waste**:
    $$\text{CPU Waste} = 39.965 \times \$0.048 = \$1.918/\text{hr}$$
    $$\text{Memory Waste} = 79.85 \times \$0.012 = \$0.958/\text{hr}$$
    $$\text{Total Waste} = \$1.918 + \$0.958 = \$2.876/\text{hr}$$

*   **Monthly Cost of Waste**:
    $$\$2.876/\text{hr} \times 730\text{ hours} = \$2,099.48/\text{month}$$

This single service wastes **over $2,000 per month** due to bad configuration defaults.

---

## 5. Clean up Lab
Delete the wasteful deployment:
```bash
kubectl delete -f ../manifests/waste-deployment.yaml
```
