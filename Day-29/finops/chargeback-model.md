# 📐 Kubernetes Multi-Tenant Chargeback & Amortization Model

This document outlines the mathematical formulas, allocation algorithms, and accounting treatments used to implement a precise, fair Kubernetes chargeback system.

---

## 1. Core Chargeback Formula

To calculate the cost of a specific workload or tenant ($T$), we must calculate both its **direct request costs** and its share of the cluster's **idle capacity** and **shared platform services**.

$$\text{Total Cost}(T) = \text{Direct Cost}(T) + \text{Shared Cost Share}(T) + \text{Idle Cost Share}(T)$$

### Where:

*   **$\text{Direct Cost}(T)$**: The cost of CPU, RAM, GPU, and PV storage requested by Pods in tenant $T$ namespaces over the billing period.
*   **$\text{Shared Cost Share}(T)$**: Pro-rata share of namespaces designated as platform services (e.g., `kube-system`, `ingress`, `monitoring`).
*   **$\text{Idle Cost Share}(T)$**: Pro-rata share of the cluster's idle capacity (the difference between node allocatable capacity and the sum of all tenant requests).

---

## 2. Mathematical Definition of Direct Costs

For a workload running across a set of nodes, the direct resource cost over a period is calculated as:

$$\text{Direct Cost}(T) = \sum_{p \in P_T} \int_{t=0}^{H} \left( \text{CPU}_{req}(p, t) \times R_{cpu}(n_p, t) + \text{RAM}_{req}(p, t) \times R_{ram}(n_p, t) \right) dt + \sum_{v \in V_T} \text{Cost}_{pv}(v)$$

*   $P_T$: The set of Pods belonging to Tenant $T$.
*   $V_T$: The set of Persistent Volumes attached to Tenant $T$.
*   $n_p$: The specific node hosting pod $p$.
*   $R_{cpu}(n, t)$ and $R_{ram}(n, t)$: The hourly rate of CPU and RAM for node $n$ at time $t$.
*   $H$: The billing period hours (e.g., 720 hours for a 30-day month).

> [!NOTE]
> If a Pod has no limits set, or has limits larger than requests, the billing calculation uses **Requests** as the billing baseline. Why? Because requests represent the capacity the scheduler *reserves* on the node, preventing other workloads from scheduling there.

---

## 3. Allocating Shared Costs (Pro-Rata Formula)

Shared platform costs (e.g., control plane, system-wide logging, API gateways) are collected in a shared bucket:

$$\text{Cost}_{shared\_system} = \sum_{ns \in \text{SharedNS}} \text{Direct Cost}(ns)$$

The proportional share for Tenant $T$ is computed using their relative size of direct resource usage:

$$\text{Shared Cost Share}(T) = \text{Cost}_{shared\_system} \times \frac{\text{Direct Cost}(T)}{\sum_{k \in \text{AllTenants}} \text{Direct Cost}(k)}$$

This ensures that larger tenants who drive more cluster traffic pay a proportionally larger share of the underlying platform costs.

---

## 4. The Amortization of Spot Savings (Spot Savings Pool)

When using Spot Instances, the price of identical VMs varies hour by hour and zone by zone. If SRE runs Team A's workload on Spot instances and Team B's workload on On-Demand instances, Team A receives a massive discount simply due to scheduler preference. This leads to friction between teams.

### Solution: The Blended Rate (Spot Savings Pool)
Instead of charging teams based on the raw spot price of the specific node their pod landed on, charge all workloads of similar priority using a cluster-wide **blended resource rate**.

$$\text{Blended Rate}_{cpu} = \frac{\sum (\text{On-Demand Nodes CPU Cost}) + \sum (\text{Spot Nodes CPU Cost})}{\text{Total Cluster Allocatable CPU}}$$

#### Benefits of Blended Amortization:
1. **Fairness**: Teams are not penalized or rewarded based on scheduler dynamics.
2. **Encourages Spot Adoption**: Since everyone's unit cost drops as Spot adoption increases, all teams are incentivized to design stateless, interruptible apps that can run on Spot nodes.
3. **Budget Stability**: Smoothens out hourly spikes in Spot pricing.
