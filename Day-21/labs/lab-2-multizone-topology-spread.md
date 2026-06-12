# 🛠️ Lab 2: Multi-Zone Workloads & Topology Spread Constraints

In this lab, you will configure zone topologies on your local cluster nodes, apply **Topology Spread Constraints** and a **Pod Disruption Budget (PDB)**, and verify scheduling decisions and eviction blocks during cluster maintenance.

---

## 🏃 Step 1: Simulate Availability Zones on Local Nodes

Since Kind is running on a single local host, nodes do not automatically receive cloud-provider zone labels. We will manually label our worker nodes to simulate three availability zones: `us-central1-a`, `us-central1-b`, and `us-central1-c`.

1. List the nodes in your cluster:
   ```bash
   kubectl get nodes
   ```

2. Label the worker nodes with zones:
   ```bash
   kubectl label node k8s-production-ops-worker topology.kubernetes.io/zone=us-central1-a
   kubectl label node k8s-production-ops-worker2 topology.kubernetes.io/zone=us-central1-b
   kubectl label node k8s-production-ops-worker3 topology.kubernetes.io/zone=us-central1-c
   ```

3. Verify the labels are applied:
   ```bash
   kubectl get nodes --show-labels | grep zone
   ```

---

## 🏃 Step 2: Deploy the Highly Available Workload

We will deploy our payment microservice and its corresponding Pod Disruption Budget.

1. Create the `production` namespace:
   ```bash
   kubectl create namespace production
   ```

2. Apply the deployment and PDB manifests:
   ```bash
   kubectl apply -f manifests/ha-app-deployment.yaml
   kubectl apply -f manifests/pod-disruption-budget.yaml
   ```

3. Wait for the pods to transition to `Running`:
   ```bash
   kubectl get pods -n production -w
   ```

---

## 🏃 Step 3: Inspect Pod Distribution

Let's verify that the Topology Spread Constraints successfully distributed the 3 replicas across the 3 availability zones we labeled.

1. Run the custom query to inspect the pods, their node names, and zone labels:
   ```bash
   kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' | while read name node; do
     zone=$(kubectl get node $node -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}')
     echo -e "$name\tNode: $node\tZone: $zone"
   done
   ```

2. **Expected Output**:
   ```text
   payment-gateway-xxxxx-xxxx   Node: k8s-production-ops-worker    Zone: us-central1-a
   payment-gateway-xxxxx-xxxx   Node: k8s-production-ops-worker2   Zone: us-central1-b
   payment-gateway-xxxxx-xxxx   Node: k8s-production-ops-worker3   Zone: us-central1-c
   ```
   *Notice how exactly 1 pod was scheduled in each of the three zones, achieving a perfect skew of 0.*

---

## 🏃 Step 4: Validate Pod Disruption Budget (PDB) Enforcement

To simulate a platform team performing node upgrades (rolling nodes), we will try to drain nodes. Our PDB requires `minAvailable: 2`. Since we only have 3 pods running, we can only afford to lose **one** pod at a time.

1. Open a second terminal window to watch the pods:
   ```bash
   kubectl get pods -n production -w
   ```

2. In your primary terminal, attempt to drain the first node (`k8s-production-ops-worker`):
   ```bash
   kubectl drain k8s-production-ops-worker --ignore-daemonsets --delete-emptydir-data
   ```
   *This should succeed. The pod on worker-01 is evicted, and rescheduled. Because Zone A is now drained, it cannot run pods, so the new pod is scheduled to Zone B or Zone C.*

3. Now, while node 1 is drained, attempt to drain the second node (`k8s-production-ops-worker2`) in parallel:
   ```bash
   kubectl drain k8s-production-ops-worker2 --ignore-daemonsets --delete-emptydir-data
   ```

4. **Expected Output**:
   ```text
   evicting pod production/payment-gateway-xxxxx-xxxx
   error when evicting pod "payment-gateway-xxxxx-xxxx" (failed to delete pod): Cannot evict pod as it would violate the pod's disruption budget.
   ```
   *The drain command blocks and keeps retrying. This proves that the Pod Disruption Budget is actively protecting your service from planned platform maintenance causing an accidental outage.*

5. Cancel the drain command (`Ctrl+C`), and uncordon the nodes to restore full health:
   ```bash
   kubectl uncordon k8s-production-ops-worker
   kubectl uncordon k8s-production-ops-worker2
   ```
