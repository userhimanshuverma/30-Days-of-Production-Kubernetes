# Lab 8: Improve Workload Efficiency (ARM64 / Graviton Transition)

In this lab, you will update a workload's scheduling rules to run on energy-efficient ARM64 (AWS Graviton, GCP Tau T2A, Azure Dpsv5) instances, yielding up to a 20% lower raw cost and 40% better price-performance.

---

## 1. Build a Multi-Architecture Container Image
To schedule a pod on ARM64 nodes, the container image must contain the binary compiled for the `linux/arm64` architecture.

Use **Docker Buildx** to build and push a multi-arch image:

```bash
# Initialize docker buildx builder instance
docker buildx create --use

# Build and push both ARM64 and AMD64 architectures to your registry
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t my-registry.company.com/apps/payment-api:v1.0.0 \
  --push .
```

---

## 2. Update Workload Scheduling Manifest
Modify your deployment spec to request ARM64 nodes first, falling back to AMD64 if capacity is unavailable.

```yaml
# deploy-multiarch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-api
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: payment-api
  template:
    metadata:
      labels:
        app: payment-api
    spec:
      affinity:
        nodeAffinity:
          # Prefer ARM64 architectures for cost optimization
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values:
                - arm64
          - weight: 10
            preference:
              matchExpressions:
              - key: kubernetes.io/arch
                operator: In
                values:
                - amd64
      containers:
      - name: payment-api
        image: my-registry.company.com/apps/payment-api:v1.0.0
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: "1"
            memory: 1Gi
```

Apply:
```bash
kubectl apply -f deploy-multiarch.yaml
```

---

## 3. Verify the Scheduled Architecture
Once the pods are running, verify the physical architecture of the nodes they were assigned to:

```bash
# Identify nodes hosting payment-api
nodes=$(kubectl get pods -l app=payment-api -o jsonpath='{.items[*].spec.nodeName}')

# Check the architecture of these nodes
for node in $nodes; do
  kubectl get node $node -o jsonpath='{.metadata.name}: {.status.nodeInfo.architecture}{"\n"}'
done
```

### Expected Output:
```
ip-192-168-10-142.ec2.internal: arm64
ip-192-168-11-205.ec2.internal: arm64
ip-192-168-12-88.ec2.internal: arm64
```

---

## 4. Cost Savings Audit
Let's compare the cost of running our payment-api pods on AWS EKS:

*   **AMD64 Node Instance (`m6i.xlarge` - 4 vCPU, 16GB RAM)**: **$0.192 / hour**
*   **ARM64 Node Instance (`m6g.xlarge` - 4 vCPU, 16GB RAM)**: **$0.154 / hour**

$$P_{\text{savings}} = \frac{0.192 - 0.154}{0.192} \times 100 \approx 19.8\%$$

By switching the platform architecture selection to Graviton (ARM64), we immediately saved **19.8%** on our compute cost without writing any new application logic.
