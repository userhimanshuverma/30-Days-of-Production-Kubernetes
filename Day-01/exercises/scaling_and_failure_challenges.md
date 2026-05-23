# 🏆 Day 1 Exercises: Compute Economics & Reconciliation Math

Complete the following architectural exercises to solidify your understanding of compute evolution and distributed systems reconciliation loops.

---

## Exercise 1: The Guest OS Tax Math

You are a platform engineer designing an infrastructure budget for a startup. You need to deploy **80 microservices**. 
* Each microservice process requires **128MB of RAM** and **0.1 vCPU** to run at baseline.
* You are choosing between two architectures:
  1. **VM-per-Service Model:** Every service runs in its own dedicated Virtual Machine. Each VM requires a minimal Linux installation that consumes **768MB of RAM** and **0.15 vCPU** just to run the guest OS system processes.
  2. **Shared Container Model:** All services run as containers on 4 larger host servers. The host container runtime and agent overhead consume a flat **1.5GB of RAM** and **0.5 vCPU** per host server.

### Questions:
1. **Total Memory (RAM) Calculation:**
   * Calculate the total RAM required on bare metal hardware to run the workload under the **VM-per-Service Model**.
   * Calculate the total RAM required under the **Shared Container Model**.
   * What percentage of RAM is wasted on Guest OS Overhead ("Guest OS Tax") in the VM model?
2. **vCPU Capacity Planning:**
   * Calculate the total vCPUs required under both models.
   * How does this affect physical host counts if each physical host has 16 vCPUs?

---

## Exercise 2: Reconciliation Loop Failure Analysis

In a Kubernetes cluster, you have defined a Deployment specifying `replicas: 4`.
Suddenly, a network partition isolates **Node 3** from the Control Plane (`kube-apiserver`).
* Pod C is running on Node 3.
* Node 3 can still run workloads locally, but it cannot communicate with the API server.
* The API Server marks Node 3 as `NotReady` after 40 seconds.

### Questions:
1. What will the `kube-controller-manager` do when Node 3 goes `NotReady`? How many Pods will it schedule, and where?
2. Node 3 recovers from the network partition 10 minutes later. Pod C is still running on Node 3.
   * What happens to the running containers on Node 3 once it reconnects to the `kube-apiserver`? Explain the state comparison steps the control plane goes through.

---

## Exercise 3: Designing for "Noisy Neighbors"

One of the biggest concerns in a shared host kernel environment (Containers) is the "Noisy Neighbor" problem—where one misconfigured application consumes all host resources, starving adjacent containers.

### Questions:
1. In standard Linux, what kernel features are used to isolate process resources?
2. If Application A writes infinitely to a local file, filling up the disk space, how does this affect Application B on the same node? Suggest how an orchestrator should limit this behavior.
