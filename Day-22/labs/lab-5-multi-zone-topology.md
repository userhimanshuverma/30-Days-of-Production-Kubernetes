# 🛠️ Lab 5: Multi-Zone Topology Spread Constraints

In this lab, you will configure topology spread constraints to distribute replicas evenly across logical zones.

---

## 🏃 Step 1: Label Nodes to Simulate Zones

If you are running in a local single-zone cluster (like Kind), we need to apply mock zone labels to nodes to simulate a multi-zone topology.

1. List your nodes:
   ```bash
   kubectl get nodes
   ```

2. Assign zone labels across your nodes:
   * Node 1 (`kind-control-plane`): Zone `us-east-1a`
     ```bash
     kubectl label nodes kind-control-plane topology.kubernetes.io/zone=us-east-1a
     ```
   * Node 2 (`kind-worker`): Zone `us-east-1b`
     ```bash
     kubectl label nodes kind-worker topology.kubernetes.io/zone=us-east-1b
     ```
   * Node 3 (`kind-worker2`): Zone `us-east-1c`
     ```bash
     kubectl label nodes kind-worker2 topology.kubernetes.io/zone=us-east-1c
     ```

3. Verify zone mapping:
   ```bash
   kubectl get nodes -L topology.kubernetes.io/zone
   ```

---

## 🏃 Step 2: Deploy Workload with Zone Spread Constraints

We will apply the manifest [topology-spread-constraints.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-22/manifests/topology-spread-constraints.yaml). This manifest defines a `maxSkew` of 1 across `topology.kubernetes.io/zone` with a hard scheduling block (`whenUnsatisfiable: DoNotSchedule`).

1. Deploy the billing worker:
   ```bash
   kubectl apply -f manifests/topology-spread-constraints.yaml
   ```

2. Watch the scheduling spread across zones:
   ```bash
   kubectl get pods -l app=billing-worker -o wide
   ```

3. **Expected Distribution**:
   Since we have 6 replicas and 3 zones, the scheduler will place exactly 2 pods in each zone.
   * `us-east-1a`: 2 pods
   * `us-east-1b`: 2 pods
   * `us-east-1c`: 2 pods

---

## 🏃 Step 3: Analyze MaxSkew Enforcement

`maxSkew` defines the maximum allowable difference in pod counts between any two topology domains.

$$\text{Skew} = \text{Current Domain Count} - \text{Minimum Matching Count in Any Domain}$$

If we scale the deployment to 7 replicas:
* Ideal spread: 3, 2, 2.
* Minimum count in any zone: 2.
* Max skew: $3 - 2 = 1$. (Allowed).

Let's check if the scheduler handles this:
1. Scale up the deployment:
   ```bash
   kubectl scale deployment billing-worker --replicas=7
   ```

2. Verify placement:
   ```bash
   kubectl get pods -l app=billing-worker -o wide
   ```
   All 7 pods should run.

3. Now, let's simulate a zone outage. Taint the nodes in zone `us-east-1c` so no more pods can run there:
   ```bash
   kubectl taint nodes kind-worker2 key=outage:NoSchedule
   ```

4. Scale the deployment up to 9 replicas:
   ```bash
   kubectl scale deployment billing-worker --replicas=9
   ```

5. Monitor pod status:
   ```bash
   kubectl get pods -l app=billing-worker
   ```

6. **Expected Result**:
   * The new pods will remain `Pending`.
   * **Why?** Since zone `us-east-1c` is tainted, no new pods can land there. The current counts are:
     * `us-east-1a`: 3 pods
     * `us-east-1b`: 3 pods
     * `us-east-1c`: 1 pod (the original remaining pod, or 0 if it crashed)
     * If a new pod is scheduled to `us-east-1a`, its count becomes 4. The skew becomes $4 - 1 = 3$ (or $4 - 0 = 4$ if none running in 1c), which exceeds `maxSkew: 1`.
     * Since `whenUnsatisfiable` is set to `DoNotSchedule`, the scheduler blocks placement.

7. Clean up taints and resources:
   ```bash
   kubectl taint nodes kind-worker2 key=outage:NoSchedule-
   kubectl delete -f manifests/topology-spread-constraints.yaml
   ```
