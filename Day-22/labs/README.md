# 🛠️ Day 22 Hands-On Labs: Index

Practice configuring scheduler internals, affinity/anti-affinity, taints/tolerations, and topology spread constraints through these labs.

---

## 📋 Labs Overview

### [Lab 1: Exploring Scheduler Internals](file:///d:/30_Days_of_Production_Kubernetes/Day-22/labs/lab-1-scheduler-internals.md)
Learn how to inspect the scheduler control loop, read scheduler log outputs, and trace how a Pod is assigned to a Node.

### [Lab 2: Implementing Node Affinity](file:///d:/30_Days_of_Production_Kubernetes/Day-22/labs/lab-2-node-affinity.md)
Deploy pods that require specific nodes based on security requirements and perform soft preferences based on hardware profiles.

### [Lab 3: Pod Affinity & Anti-Affinity](file:///d:/30_Days_of_Production_Kubernetes/Day-22/labs/lab-3-pod-affinity-anti-affinity.md)
Implement high availability scheduling by preventing pods from running on the same host, and co-locate caching services next to API containers.

### [Lab 4: Workload Isolation via Taints & Tolerations](file:///d:/30_Days_of_Production_Kubernetes/Day-22/labs/lab-4-taints-tolerations.md)
Taint nodes to isolate dedicated GPU compute pools, deploy GPU training jobs with correct tolerations and affinities, and test pod exclusion.

### [Lab 5: Multi-Zone Topology Spread Constraints](file:///d:/30_Days_of_Production_Kubernetes/Day-22/labs/lab-5-multi-zone-topology.md)
Distribute pods evenly across multiple availability zones and control the maximum skew during scale-up.
