# 🛠️ Lab 2: Implementing Node Affinity

In this lab, you will label cluster nodes and apply both required (hard) and preferred (soft) node affinity constraints to workloads.

---

## 🏃 Step 1: Label Cluster Nodes

First, simulate a production cluster setup by assigning security and hardware labels to your nodes.

1. List your nodes:
   ```bash
   kubectl get nodes
   ```

2. Assign the label `security-zone=pci-compliant` to one node (e.g. `kind-worker` or your custom worker node name):
   ```bash
   kubectl label nodes kind-worker security-zone=pci-compliant
   ```

3. Assign the label `disk-type=ssd` to the same node:
   ```bash
   kubectl label nodes kind-worker disk-type=ssd
   ```

4. Verify labels are set:
   ```bash
   kubectl get nodes --show-labels | grep security-zone
   ```

---

## 🏃 Step 2: Deploy the Workload with Node Affinity

We will use the manifest [pod-node-affinity.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-22/manifests/pod-node-affinity.yaml) created earlier.

1. Apply the deployment manifest:
   ```bash
   kubectl apply -f manifests/pod-node-affinity.yaml
   ```

2. Watch the pods state:
   ```bash
   kubectl get pods -l app=payment-api -o wide
   ```

3. **Expected Result**: 
   All 3 replicas should schedule successfully and run **exclusively** on the node labeled `security-zone=pci-compliant` (`kind-worker`). The scheduler matched the hard constraint and scored `kind-worker` higher due to the soft preference for `disk-type=ssd`.

---

## 🏃 Step 3: Test Hard Constraint Failure

Let's see what happens if we request a constraint that cannot be met.

1. Create a pod requesting a non-existent security zone:
   ```yaml
   # Save as security-fail-pod.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: secure-fail
   spec:
     containers:
     - name: nginx
       image: nginx:alpine
     affinity:
       nodeAffinity:
         requiredDuringSchedulingIgnoredDuringExecution:
           nodeSelectorTerms:
           - matchExpressions:
             - key: security-zone
               operator: In
               values:
               - hipaa-compliant
   ```

2. Apply the pod:
   ```bash
   kubectl apply -f security-fail-pod.yaml
   ```

3. Inspect pod status:
   ```bash
   kubectl get pod secure-fail
   ```
   *Status*: `Pending`

4. Diagnose scheduling rejection:
   ```bash
   kubectl describe pod secure-fail
   ```
   *Expected Event message*:
   `0/3 nodes are available: 3 node(s) didn't match PodFields/PodAntiAffinity or NodeAffinity.`

This proves that `requiredDuringSchedulingIgnoredDuringExecution` is a strict, hard filter. The pod will remain pending until a node is labeled `security-zone=hipaa-compliant`.

5. Clean up resources:
   ```bash
   kubectl delete pod secure-fail
   kubectl delete -f manifests/pod-node-affinity.yaml
   ```
