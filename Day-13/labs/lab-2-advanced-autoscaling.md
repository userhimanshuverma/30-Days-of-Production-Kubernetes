# 🛠️ Lab 2: Advanced Autoscaling (Kafka, CA, Custom Policies)

Explore event-driven scaling, cluster infrastructure expansion, and custom scaling policies.

---

## Lab 6: Scaling Kafka Consumers via KEDA

To scale workloads based on metrics that do not live inside the container (like Kafka consumer lag or AWS SQS message queue depth), we use **KEDA** (Kubernetes Event-driven Autoscaling).

### Step 1: Install KEDA
Add the Helm repository and install KEDA:
```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install keda kedacore/keda --namespace keda --create-namespace
```

Verify KEDA controllers are active:
```bash
kubectl get pods -n keda
```

### Step 2: Deploy Workload & ScaledObject
Apply the consumer deployment and the KEDA ScaledObject resource:
```bash
kubectl apply -f ../manifests/kafka-consumer.yaml
```

Inspect the generated HPA managed by KEDA:
```bash
kubectl get hpa
```
*Note that KEDA automatically generates and updates a standard HPA under the hood, translating the `lagThreshold` calculations into scaling decisions.*

---

## Lab 7: Simulating Cluster Autoscaler Node Provisioning

Because local clusters run on a single host, we will mock a Cluster Autoscaler scale-up event by creating resource exhaustion and observing pod scheduler diagnostics.

### Step 1: Request Massive CPU Reservations
Create a deployment that requests far more CPU than your local node pool can allocate (e.g. requesting `20 CPUs` in total):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynamic-exhaustion-app
spec:
  replicas: 4
  selector:
    matchLabels:
      app: exhaust
  template:
    metadata:
      labels:
        app: exhaust
    spec:
      containers:
      - name: container
        image: busybox
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: "5" # 5 CPU requests per replica = 20 CPU total
            memory: "2Gi"
```
Save the file as `exhaustion.yaml` and apply it:
```bash
kubectl apply -f exhaustion.yaml
```

### Step 2: Observe Pending Status
List the pods to find them stuck in a `Pending` state:
```bash
kubectl get pods -l app=exhaust
```

Describe a pending pod to find the scheduling failure reason:
```bash
kubectl describe pod -l app=exhaust | grep -A 5 Events
```
*Expected output message: `0/1 nodes are available: 1 Insufficient cpu.`*

*In a live production environment, the **Cluster Autoscaler** daemon reads this scheduler event, matches it to a node-group size template, and provisions a new VM from the cloud provider to host the pod.*

### Clean Up
Delete the exhaustion deployment:
```bash
kubectl delete deployment dynamic-exhaustion-app
rm exhaustion.yaml
```

---

## Lab 8: Fine-Tuning HPA Scaling Policies

In this lab, we will configure an HPA to scale out instantly under load but scale down slowly, preventing service thrashing.

### Step 1: Apply Custom Behavior
Ensure the HPA from `manifests/hpa-cpu-memory.yaml` is deployed:
```bash
kubectl apply -f ../manifests/hpa-cpu-memory.yaml
```

### Step 2: Analyze behavior properties in YAML
```yaml
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300
```
* **`scaleUp.stabilizationWindowSeconds: 0`:** Ingress spikes require immediate attention. Setting this to 0 bypasses HPA scale-up delay.
* **`scaleDown.stabilizationWindowSeconds: 300`:** Tells the HPA controller that when utilization falls below the 60% threshold, it must wait for a 5-minute (300s) rolling window of sustained low utilization before triggering a scale-down, protecting your API from rapid scale fluctuations.
