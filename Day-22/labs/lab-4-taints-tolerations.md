# 🛠️ Lab 4: Isolating Workloads via Taints & Tolerations

In this lab, you will isolate worker nodes using taints and deploy workloads that tolerate and target those nodes for specialized compute (simulating GPU pools).

---

## 🏃 Step 1: Add a Taint to a Worker Node

Taint a node to ensure standard application workloads do not schedule on it.

1. Pick a worker node (e.g. `kind-worker2`):
   ```bash
   kubectl get nodes
   ```

2. Add a `NoSchedule` taint to `kind-worker2`:
   ```bash
   kubectl taint nodes kind-worker2 hardware=gpu:NoSchedule
   ```

3. Verify the taint is active:
   ```bash
   kubectl describe node kind-worker2 | grep Taints
   ```
   *Expected Output*:
   `Taints:             hardware=gpu:NoSchedule`

---

## 🏃 Step 2: Verify Node Repels Standard Workloads

1. Deploy a standard web server with multiple replicas:
   ```bash
   kubectl create deployment web-standard --image=nginx:alpine --replicas=5
   ```

2. Inspect pod placement:
   ```bash
   kubectl get pods -o wide -l app=web-standard
   ```

3. **Analysis**:
   You will notice that **none** of the `web-standard` pods scheduled onto `kind-worker2`. The scheduler automatically filtered out `kind-worker2` because the pods did not tolerate the `hardware=gpu` taint.

---

## 🏃 Step 3: Run the GPU Workload (Tolerated + Targeted)

We will use the manifest [taint-toleration-gpu.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-22/manifests/taint-toleration-gpu.yaml). This manifest has:
* A `toleration` to allow running on tainted `hardware=gpu` nodes.
* A `nodeAffinity` statement to force the pod onto `hardware=gpu` labeled nodes.

1. First, label `kind-worker2` with `hardware=gpu` to satisfy the Node Affinity statement:
   ```bash
   kubectl label nodes kind-worker2 hardware=gpu
   ```

2. Apply the training job manifest:
   ```bash
   kubectl apply -f manifests/taint-toleration-gpu.yaml
   ```

3. Monitor the job pod status:
   ```bash
   kubectl get pods -l app=gpu-trainer -o wide
   ```

4. **Expected Result**:
   The GPU training pod schedules successfully on the tainted node `kind-worker2`. It matches both the taint toleration (allowing it to schedule) and node affinity (directing it to that specific node).

---

## 🏃 Step 4: Clean Up Taints & Resources

Always remove taints after testing to return the cluster to standard operations.

1. Remove the taint from `kind-worker2` (notice the minus sign at the end of the command):
   ```bash
   kubectl taint nodes kind-worker2 hardware=gpu:NoSchedule-
   ```

2. Remove the node label:
   ```bash
   kubectl label nodes kind-worker2 hardware-
   ```

3. Clean up resources:
   ```bash
   kubectl delete deployment web-standard
   kubectl delete -f manifests/taint-toleration-gpu.yaml
   ```
