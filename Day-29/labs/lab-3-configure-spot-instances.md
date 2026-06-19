# Lab 3: Configure Spot Instances

In this lab, you will deploy a spot-ready workload configured with affinity, tolerations, and a Pod Disruption Budget (PDB), ensuring it schedules on Spot instances and gracefully handles interruptions.

---

## 1. Apply Spot Provisioning Manifest
If you have Karpenter configured in your cluster, apply the Spot-first provisioner manifest:

```bash
kubectl apply -f ../manifests/karpenter-provisioner.yaml
```

This specifies that any pending pod requesting the `karpenter.sh/capacity-type: spot` label or matching the tolerations can trigger a spot-capacity EC2 node creation.

---

## 2. Deploy the Spot-Ready Workload
Deploy the batch processing worker workload:

```bash
kubectl apply -f ../manifests/spot-deployment.yaml
```

Verify that the pods are created:
```bash
kubectl get pods -l app=batch-worker -o wide
```

---

## 3. Verify Node Scheduling Properties
Let's verify what nodes these pods landed on and check their capacity-type flags.

```bash
# Get the node names hosting our batch-worker pods
nodes=$(kubectl get pods -l app=batch-worker -o jsonpath='{.items[*].spec.nodeName}')

# Check the capacity-type label on those nodes
for node in $nodes; do
  echo "Node: $node"
  kubectl get node $node --show-labels | tr "," "\n" | grep -E "capacity-type|capacityType|gke-spot"
done
```

### Expected Output:
```
Node: ip-192-168-45-12.ec2.internal
karpenter.sh/capacity-type=spot
```
*(If you are running in a local Kind/Minikube cluster, the nodes will lack this label. The scheduling will fallback to default nodes because we configured `preferredDuringSchedulingIgnoredDuringExecution` instead of `required`.)*

---

## 4. Test Pod Disruption Budget (PDB) Protection
We configured a PodDisruptionBudget for the workers to prevent aggressive manual drains or updates from knocking down all processing replicas.

Verify the PDB status:
```bash
kubectl get pdb batch-worker-pdb
```

### Expected Output:
```
NAME               MIN AVAILABLE   ALLOWED DISRUPTIONS   AGE
batch-worker-pdb   60%             2                     5m
```

If we attempt to perform a drain on a node hosting these pods, Kubernetes will prevent the drain if evicting the pods would drop active replicas below **60%** (3 out of 5 pods).

---

## 5. Simulate a Spot Interruption Event
In production, Karpenter listens to the AWS Interruption SQS Queue. You can simulate a spot interruption event manually by cordoning and draining the spot node:

```bash
# Select one spot node hosting a pod
target_node=$(kubectl get pods -l app=batch-worker -o jsonpath='{.items[0].spec.nodeName}')

# Drain the node (simulating a 2-minute interruption notice execution)
kubectl drain $target_node --ignore-daemonsets --delete-emptydir-data --force
```

Watch the pod logs to observe the graceful shutdown:
```bash
kubectl get pods -w -l app=batch-worker
```

You should see:
1. The old pod on the drained node shifts to `Terminating`.
2. A new pod schedules onto an alternative node immediately.
3. The terminating pod catches the `SIGTERM` signal, flushes queues, sleeps for 10 seconds, and exits cleanly (exit code 0).

---

## 6. Clean up Lab
```bash
kubectl uncordon $target_node
kubectl delete -f ../manifests/spot-deployment.yaml
```
