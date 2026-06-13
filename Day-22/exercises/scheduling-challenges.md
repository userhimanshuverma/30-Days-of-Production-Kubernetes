# 🏆 Day 22: Scheduling Coding Challenges

Solve the following placement challenges by writing and applying valid Kubernetes manifests.

---

## 🎯 Challenge 1: The PCI-DSS Compliant Deployment

### 📋 Scenario:
You have a credit card processing API (`payment-processor`) that must only run on nodes labeled as `pci-compliant=true`. Additionally, the database team prefers (but does not require) that these pods run on nodes with `disk-type=ssd` to optimize read/write latency.

### 🛠️ Tasks:
1. Create a Kubernetes deployment YAML named `payment-processor-deployment.yaml`.
2. Configure 3 replicas of the container `nginx:alpine`.
3. Add a **hard node affinity** rule to target `pci-compliant=true`.
4. Add a **soft node affinity** rule (weight 100) to prefer `disk-type=ssd`.
5. Run a dry-run check to verify manifest validity:
   ```bash
   kubectl apply -f payment-processor-deployment.yaml --dry-run=client
   ```

---

## 🎯 Challenge 2: High Availability Web Spread

### 📋 Scenario:
You are launching a web application frontend (`web-frontend`). In order to ensure maximum resilience, you want to guarantee that **no two replicas run on the same physical VM host**. 

### 🛠️ Tasks:
1. Create a deployment YAML named `web-frontend-ha.yaml` with 3 replicas.
2. Add a **hard pod anti-affinity** rule so replicas repel other pods with label `app: web-frontend`.
3. Set the `topologyKey` to `kubernetes.io/hostname`.
4. Verify using a local cluster (e.g. Kind or Minikube) that the pods schedule to separate nodes. (If you scale the deployment replicas beyond your node count, excess pods should stay `Pending`).

---

## 🎯 Challenge 3: System Node Pool Isolation

### 📋 Scenario:
You have sensitive system monitoring daemon agents (`sys-agent`). You have dedicated system nodes in your cluster tainted with `role=system:NoSchedule` to keep standard application workloads away. You want to make sure your monitoring daemon schedules successfully on these nodes.

### 🛠️ Tasks:
1. Write a DaemonSet manifest `sys-agent-daemonset.yaml`.
2. Add the correct `tolerations` block matching the taint `role=system:NoSchedule`.
3. Add a `nodeAffinity` block to force the DaemonSet to run *only* on nodes carrying the label `role=system`.
4. Apply the manifest and verify the daemonset scheduling status.
