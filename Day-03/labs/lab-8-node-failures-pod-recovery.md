# Lab 8: Node Failures and Pod Recovery

In a distributed system, failures are inevitable. When a node goes offline, Kubernetes must detect the failure, update node status, and reschedule workloads. In this lab, you will simulate a node failure in your Kind cluster and observe the complete lifecycle of node eviction and pod recovery.

---

## 🏃 Step 1: Deploy a Test Workload
We will deploy a ReplicaSet with 4 replicas, ensuring they are distributed across our worker nodes.

Write the following manifest to `manifests/01-nginx-deployment.yaml` (or update it):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resilience-demo
  namespace: default
spec:
  replicas: 4
  selector:
    matchLabels:
      app: resilience-demo
  template:
    metadata:
      labels:
        app: resilience-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
```
Apply the deployment:
```bash
kubectl apply -f manifests/01-nginx-deployment.yaml
```

List the pods and check their node assignments:
```bash
kubectl get pods -o wide -l app=resilience-demo
```
*Note which pods are running on `k8s-internals-worker` vs `k8s-internals-worker2`.*

---

## 🏃 Step 2: Simulate Node Shutdown
Since we are using Kind, each node runs as a Docker container. We can simulate a complete node crash (e.g., power loss, kernel panic) by stopping the docker container for `k8s-internals-worker`.

On your host machine, stop the container:
```bash
docker stop k8s-internals-worker
```

---

## 🏃 Step 3: Monitor Node Status Transitions
Immediately start monitoring node states:
```bash
kubectl get nodes -w
```

**What happens next?**
1. **Heartbeat Failure:** The Kubelet on `k8s-internals-worker` is no longer sending its lease renewal heartbeats to the API Server.
2. **Node Lease Expiry:** After approximately 40 seconds (the default `--node-monitor-grace-period` evaluated by the Node Lifecycle Controller), the node transitions:
   ```
   NAME                           STATUS     ROLES    AGE
   k8s-internals-worker           NotReady   <none>   10m
   ```

---

## 🏃 Step 4: Trace Pod Eviction Timings
List the pods again:
```bash
kubectl get pods -o wide -l app=resilience-demo
```
**Observation:**
You will notice that the pods assigned to `k8s-internals-worker` are still listed, but their status may have changed to `Terminating` or `Unknown`. They are **not** immediately deleted and replaced on the other node.

### Why is there a delay?
Kubernetes avoids aggressive eviction to prevent split-brain scenarios (where a transient network split causes nodes to reschedule workloads that are still running).
* **Eviction Timeout:** By default, every pod is automatically injected with two tolerations upon creation:
  * `node.kubernetes.io/unreachable:NoExecute` with `tolerationSeconds: 300`
  * `node.kubernetes.io/not-ready:NoExecute` with `tolerationSeconds: 300`
* This means that if a node goes `NotReady` or `Unreachable`, the Controller Manager will wait **5 minutes (300 seconds)** before forcibly evicting the pods.

If you wait for 5 minutes, you will observe the following in your events:
1. The Pods on `k8s-internals-worker` are marked for eviction.
2. The ReplicaSet Controller detects that the actual count of running pods has dropped below 4.
3. The controller requests the creation of replacement pods.
4. The Scheduler schedules the replacement pods onto the surviving node `k8s-internals-worker2`.

Verify the final state:
```bash
kubectl get pods -o wide -l app=resilience-demo
```
*All 4 running replicas should now be located on `k8s-internals-worker2`.*

---

## 🏃 Step 5: Recover the Node and Verify Reconciliation
Let's turn the failed node back on:
```bash
docker start k8s-internals-worker
```

Monitor the node status:
```bash
kubectl get nodes -w
```
Once the container boots, the Kubelet starts, connects to the API Server, and reports `Ready`.

### What happens to the old pods?
The Kubelet on the recovered node checks the API Server's current list of scheduled pods. It detects that its local containers (which were running when the node crashed) belong to pods that have already been marked as deleted/evicted in etcd.
The Kubelet calls the container runtime to stop and clean up those containers.

Clean up the deployment:
```bash
kubectl delete deployment resilience-demo
```
