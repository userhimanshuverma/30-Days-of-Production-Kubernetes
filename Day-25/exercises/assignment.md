# 🏆 Day 25: Hands-On Assignment - Multi-Region Affinity & Override Policies

In this challenge, you will implement a custom propagation policy, customize memory allocations per region, and write a verification script to audit latency metrics.

---

## 🎯 Objectives
1.  Configure a propagation policy that matches cluster version labels.
2.  Apply overrides to configure higher CPU/Memory limits for one cluster.
3.  Write a script to verify routing endpoints and calculate latencies.

---

## 💻 Tasks

### Task 1: Write a Version-Aware Propagation Policy
Create a propagation policy file named `exercises/my-propagation.yaml`.
*   It must match a deployment named `payment-api`.
*   It must schedule the workloads across available clusters.
*   **Restriction**: Use `clusterAffinity` with `labelSelector` terms to target only clusters labeled with `kubernetes.io/arch: amd64` and where the version label matches `>= 1.25.0`.

### Task 2: Configure Region-Specific Resource Limits
Create an override policy named `exercises/my-override.yaml` that modifies the deployment resource definitions:
*   For `kind-east`: Set container CPU limit to `200m` and Memory limit to `256Mi`.
*   For `kind-west`: Set container CPU limit to `400m` and Memory limit to `512Mi` (since the West cluster is configured on higher-performance hardware).
*   Add a cluster-specific environment variable `CLUSTER_IDENTIFIER` reflecting the regional name.

### Task 3: Write the Verification Script
Write a bash script named `exercises/verify-routing.sh` that performs the following actions:
1.  Query the local kubeconfigs to verify that the `payment-api` replicas are running with the expected counts in each cluster.
2.  Parse the deployment specification in both clusters and output the configured CPU/Memory resource limit fields to confirm the overrides were applied.
3.  Execute a loop that makes 10 HTTP requests to the public ingress points of both clusters, calculating the average response latency (using `curl -w "%{time_starttransfer}\n"`) and outputting a comparison table.

---

## 📤 Submission Guidelines
Submit your solution folder containing:
*   `my-propagation.yaml`
*   `my-override.yaml`
*   `verify-routing.sh`
*   A brief markdown summary (`report.md`) detailing:
    1.  The output of your verification script showing resource configurations.
    2.  A brief analysis explaining the latency difference between the two cluster ingresses and how your GeoDNS rules mitigate this.
