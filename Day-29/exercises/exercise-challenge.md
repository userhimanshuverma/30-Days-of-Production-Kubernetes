# 🏆 Day 29 Exercise: Cluster Cost Defragmentation & Hardening

In this challenge, you will take a wasteful microservice deployment and refactor it into an optimized, highly resilient, and cost-efficient Kubernetes workload.

---

## 1. The Scenario

You are the lead FinOps SRE for a retail platform. The `checkout-service` deployment has been flagged by the finance team for costing **$3,400/month** despite running a simple web gateway.

Here is the current, wasteful manifest:

```yaml
# wasteful-checkout.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-service
spec:
  replicas: 8
  selector:
    matchLabels:
      app: checkout-service
  template:
    metadata:
      labels:
        app: checkout-service
    spec:
      containers:
      - name: checkout-api
        image: nginx:alpine
        resources:
          requests:
            cpu: "3"
            memory: 6Gi
          limits:
            cpu: "3"
            memory: 6Gi
```

### Measured Historical Metrics (Last 7 Days):
*   **Average CPU usage**: `120m` per pod.
*   **Peak CPU usage**: `350m` (during checkout traffic bursts).
*   **Average Memory usage**: `220Mi` (steady state).
*   **Peak Memory usage**: `410Mi` (under heavy load).

---

## 2. Your Assignment

Create a new file `optimized-checkout.yaml` inside the exercises directory. It must satisfy the following criteria:

1.  **Right-Sized Resources**:
    *   CPU request must be set to peak CPU usage + 25% safety buffer.
    *   CPU limit must be set to 1.5x of the request to handle micro-bursts.
    *   Memory request must be set to peak memory usage + 30% safety buffer.
    *   Memory limit must be set to 1.5x of the memory request to prevent OOMKills.
2.  **Spot Capability**:
    *   Configure Node Affinity to **prefer** `karpenter.sh/capacity-type: spot` (Weight: 100).
    *   Add Tolerations for Spot node taints (key: `kubernetes.azure.com/scalesetpriority`, `sku`, and `karpenter.sh/capacity-type`).
3.  **High Availability Protections**:
    *   Add a `PodDisruptionBudget` ensuring at least **50%** of pods remain available during spot reclaims or nodes updates.
    *   Set `terminationGracePeriodSeconds: 45` to allow active payments to finish.
4.  **Autoscaling**:
    *   Deploy a HorizontalPodAutoscaler targeting the deployment.
    *   Replicas: min `2`, max `10`.
    *   Target CPU utilization: `70%`.
    *   Include a `scaleDown` stabilization window of **4 minutes** (`240` seconds) to prevent thrashing.

---

## 3. Verification Commands

Verify the syntax and apply the optimized manifest to your local test cluster (Kind/Minikube):

```bash
# Apply manifest
kubectl apply -f optimized-checkout.yaml

# Verify HPA configuration
kubectl describe hpa checkout-hpa

# Verify PDB configuration
kubectl describe pdb checkout-pdb
```

Submit your `optimized-checkout.yaml` file along with the output logs showing running pods and the HPA/PDB statuses.
