# Lab 4: Optimize Node Utilization

In this lab, you will configure Karpenter's Consolidation policies to automatically optimize node utilization, packing pods efficiently to minimize the total active node count.

---

## 1. Inspect Current Node Utilization & Allocation

To determine how well-packed your cluster is, look at the allocation of resources against physical capacity:

```bash
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Typical Fragmented Cluster Output:
```
Allocated resources:
  Resource           Requests    Limits
  --------           --------    ------
  cpu                850m (21%)  2000m (50%)
  memory             1024Mi (14%) 2048Mi (28%)
```
This node is only utilizing **21% of CPU requests**, yet it is running. If multiple nodes look like this, we are paying for idle capacity.

---

## 2. Deploy Fragmented Workloads

Deploy three separate small deployments, simulating independent apps running on different nodes (due to anti-affinity or random scheduling):

```yaml
# fragmented-apps.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-a
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-a
  template:
    metadata:
      labels:
        app: app-a
    spec:
      containers:
      - name: container
        image: alpine
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-b
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-b
  template:
    metadata:
      labels:
        app: app-b
    spec:
      containers:
      - name: container
        image: alpine
        command: ["sleep", "3600"]
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
```

Deploy:
```bash
kubectl apply -f fragmented-apps.yaml
```

---

## 3. Enable Karpenter Consolidation

Ensure that your Karpenter NodePool has consolidation enabled under the `disruption` block. This tells Karpenter to look for consolidation opportunities:

```yaml
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
```

Apply the configuration:
```bash
kubectl apply -f ../manifests/karpenter-provisioner.yaml
```

---

## 4. Observe Workload Consolidation

When consolidation triggers:
1. Karpenter analyzes whether `app-a` and `app-b` (currently on separate nodes) can fit onto a single node.
2. If they fit, Karpenter issues a delete command for the extra node.
3. The pods on the deleted node are evicted and scheduled onto the remaining node.

Observe this live:
```bash
kubectl get nodes -w
```
And inspect Karpenter controller logs:
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100 | grep -i "consolidat"
```

### Expected Log Output:
```
2026-06-19T20:30:12Z INFO controller.disruption consolidating node ip-192-168-12-84.ec2.internal via replace with node ip-192-168-15-20.ec2.internal, saving $45.10/month
2026-06-19T20:30:35Z INFO controller.disruption deleted node ip-192-168-12-84.ec2.internal
```

Karpenter automatically calculated that replacing the node would save **$45.10/month** and executed the plan safely in 23 seconds.

---

## 5. Clean up Lab
```bash
kubectl delete -f fragmented-apps.yaml
```
