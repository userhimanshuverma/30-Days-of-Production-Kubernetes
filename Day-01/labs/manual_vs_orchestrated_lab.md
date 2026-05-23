# 🧪 Lab 1: Manual vs. Orchestrated Infrastructure

In this lab, you will use the **Interactive Infrastructure Evolution Simulator** to visualize the behavior of Bare Metal, Virtualization, standalone Docker, and Kubernetes under load spikes and node failures.

---

## 🎯 Lab Objectives
1. Compare manual container lifecycle operations with declarative Kubernetes workflows.
2. Experience how system load and scaling constraints impact performance.
3. Simulate node failures and compare manual recovery overhead against automatic self-healing.

---

## 🛠️ Step 1: Open the Infrastructure Simulator
Open [kubernetes-evolution-simulator.html](kubernetes-evolution-simulator.html) in your browser:
* Or open the file path directly: [Day-01/labs/kubernetes-evolution-simulator.html](file:///d:/30_Days_of_Production_Kubernetes/Day-01/labs/kubernetes-evolution-simulator.html) in your web browser.

---

## 📦 Step 2: The Bare Metal Era (Manual Labor)

1. Select the **Bare Metal** era button.
2. Click **Scale Workload (+1 Pod)**.
   * *Observation:* Note the provisioning delay and event log message: `Manual provision request successful`.
3. Click **Crash Server Node**.
   * *Observation:* Notice that the server node border turns red, its status blinks `DOWN`, and your active load immediately drops. The event log records: `Lost services due to node crash. Manual recovery required.`
4. Try to click **Scale Workload** again.
   * *Observation:* If all servers are crashed, you will get the error: `Deployment failed: No server capacity`.
5. **Key Takeaway:** In Bare Metal, there is no self-healing. Hardware failure = downtime until you manually fix it.

---

## 💻 Step 3: The VM Era (Resource Overhead)

1. Select the **Virtualization (VMs)** era.
2. Look at the **Resource Fragmentation** telemetry on the right.
   * *Observation:* Notice that fragmentation leaps to **75% (Reserved Waste)**.
3. Scale the workload up to 4 units.
   * *Observation:* Notice how quickly CPU and memory usage climb, even with low workload. This is because every VM carries its own 1GB+ Guest OS allocation payload.
4. **Key Takeaway:** VMs improved scaling speed, but introduced massive resource waste due to OS replication.

---

## 🐳 Step 4: Standalone Docker (The Orphan Containers)

1. Select the **Docker Containers** era.
2. Scale the workload up to 6 units.
   * *Observation:* The containers launch in seconds. Resource utilization stays optimized (shared host kernel).
3. Click **Crash Server Node**.
   * *Observation:* A node crashes. The containers running on that node change to a red, crashed state. Your active load decreases.
4. Wait 10 seconds.
   * *Observation:* Do the containers recover? No. Because standalone Docker has no centralized control plane watching the cluster. The container daemon on the crashed host is dead.
5. **Key Takeaway:** Containers solve packaging and density, but do not solve cluster availability or high availability.

---

## ☸️ Step 5: The Kubernetes Era (Self-Healing & Declarative State)

1. Select the **Kubernetes Orchestration** era.
2. Scale the workload to 6 replicas.
   * *Observation:* Look at the **Kubernetes Control Plane** panel on the right. Watch the **Reconciliation Loop** cycle through:
     1. `Observe State` (reads actual running pods).
     2. `Analyze Diff` (compares actual vs. desired configuration in etcd).
     3. `Act to Reconcile` (creates or destroys pods).
3. Click **Crash Server Node** to take down a node.
   * *Observation:*
     * Immediately, the nodes go red. Pods on that node crash.
     * The event log shows: `Node transition to NotReady. Rescheduling scheduled.`
     * Watch the Reconciliation Loop on the right immediately activate.
     * Within 2 seconds, Kubernetes schedules replacement pods on the remaining healthy nodes.
     * The cluster status returns to **HEALTHY** and the reconciliation log updates to `SECURED`.
4. Click **Simulate Traffic Spike**.
   * *Observation:* HPA detects the CPU surge and automatically increases desired replicas, spreading them across remaining healthy hosts.
5. **Key Takeaway:** Kubernetes abstracts the physical servers. You declare the desired state, and the control plane works endlessly to maintain that state, regardless of hardware failures or traffic spikes.
