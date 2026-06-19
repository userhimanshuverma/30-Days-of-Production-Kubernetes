# Lab 7: Reduce Cluster Costs

In this lab, you will write scripts and run commands to identify orphaned Persistent Volumes (PVs), identify underutilized nodes, and implement scheduled scale-downs for non-production namespaces.

---

## 1. Clean Up Orphaned Persistent Volumes (PVs)
When a namespace or deployment is deleted, associated PersistentVolumeClaims (PVCs) are sometimes left behind, or PVs with a `ReclaimPolicy` of `Retain` remain allocated in the cloud, billing your account endlessly.

Run the following command to find any PVs that are in the `Released` or `Available` state (meaning they are not actively mounted by any pod):

```bash
kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released" or .status.phase=="Available") | .metadata.name'
```

### Expected Output:
```
pvc-9a8b7c6d-5e4f-3a2b-1c0d-e9f8a7b6c5d4
```

To release the storage cost, delete these orphaned PVs:
```bash
# Extract and delete released PVs
kubectl get pv -o json | jq -r '.items[] | select(.status.phase=="Released") | .metadata.name' | xargs -I {} kubectl delete pv {}
```

---

## 2. Identify and Consolidate Idle Nodes
If you have nodes with extremely low pod allocations, they represent pure financial waste.

Let's query the resource requests per node:
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU_REQUESTS:.status.allocatable.cpu | grep -v NAME
```

For nodes hosting only DaemonSets or system agents, cordon and drain them to force consolidation:
```bash
# Identify underutilized node
target_node="ip-192-168-33-14.ec2.internal"

# Cordon and drain
kubectl cordon $target_node
kubectl drain $target_node --ignore-daemonsets --delete-emptydir-data --force
```

Cloud autoscalers will automatically terminate the node instance within 10 minutes when it detects the node has been empty.

---

## 3. Configure Off-Hours Cron Scaling
Non-production environments (development, staging) often run 24/7, even though developers only work 8–10 hours a day. Scaling non-production namespaces to 0 replicas during off-hours yields a **~60% cost reduction** immediately.

Let's deploy a `CronJob` that scales deployments down at 8:00 PM and back up at 8:00 AM on weekdays.

### Apply the Scale-Down CronJob:
```yaml
# cron-scale-down.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: dev-scale-down
  namespace: default
spec:
  schedule: "0 20 * * 1-5" # 8:00 PM Monday through Friday
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cluster-scaler-sa # Requires RBAC permissions to update deployments
          restartPolicy: OnFailure
          containers:
          - name: scaler
            image: bitnami/kubectl:latest
            command:
            - sh
            - -c
            - "kubectl scale deployment --all --replicas=0 -n dev-namespace"
```

Create and apply this CronJob in your development clusters to automate off-hours savings.
```bash
kubectl apply -f cron-scale-down.yaml
```
*(Make sure to create a matching `dev-scale-up` CronJob with schedule `0 8 * * 1-5` and `--replicas=2` to restore capacity before the team starts work!)*
