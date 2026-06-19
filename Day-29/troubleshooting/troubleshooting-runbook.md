# 🚨 Troubleshooting Cost & Performance Outages

This runbook provides diagnostic commands, symptoms, root causes, and resolutions for cost and performance-related failures in Kubernetes clusters.

---

## Scenario 1: CPU Throttling causing Latency Spikes
*   **Symptoms**: API latency increases under load, but CPU utilization is reported below 60%. Prometheus logs show high CFS throttled times.
*   **Diagnostics Command**:
    ```bash
    # Check throttled periods in container
    kubectl exec -n monitoring prometheus-k8s-0 -- wget -qO- 'http://localhost:9090/api/v1/query?query=sum(rate(container_cpu_cfs_throttled_periods_total[5m]))by(pod)' | jq
    ```
*   **Root Cause**: The container's CPU limit is set too low. The Linux kernel CFS scheduler freezes the threads during peak periods to enforce limits.
*   **Resolution**: Increase the container's CPU limit, or remove CPU limits entirely if requests are correctly sized.
*   **Prevention**: Set CPU Limits equal to 1.5x - 3x of Requests. Never set requests and limits to the exact same low value.

---

## Scenario 2: Container terminated via OOMKilled (Exit Code 137)
*   **Symptoms**: Pods restart randomly. Logs show no internal application crash errors. Pod description shows `Last State: Terminated` with reason `OOMKilled`.
*   **Diagnostics Command**:
    ```bash
    # View pod termination details
    kubectl describe pod <pod-name> | grep -A 2 -i "Last State"
    ```
*   **Root Cause**: The container exceeded its configured memory limit. The Linux kernel terminated the process using SIGKILL (exit code 137).
*   **Resolution**: Increase `resources.limits.memory` in the deployment manifest. If the memory footprint grows continuously, audit the code for memory leaks.
*   **Prevention**: Set Memory Limits with a 30-50% buffer above the maximum observed historical memory usage.

---

## Scenario 3: Spot Instance Interruption Outage
*   **Symptoms**: Multiple pods restart or go pending simultaneously, causing transient API connection errors (502/504 Bad Gateway).
*   **Diagnostics Command**:
    ```bash
    # Find events related to spot terminations
    kubectl get events --sort-by='.metadata.creationTimestamp' | grep -i -E "evict|drain|node"
    ```
*   **Root Cause**: A large spot reclaim event occurred, and the application lacked a Pod Disruption Budget (PDB) or was not distributed across multiple nodes/zones.
*   **Resolution**:
    1. Deploy a PodDisruptionBudget to protect the microservice.
    2. Configure node affinities to allow scheduling across both Spot and On-Demand pools.
*   **Prevention**: Use `topologySpreadConstraints` to enforce zone and host spreading:
    ```yaml
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: my-app
    ```

---

## Scenario 4: Pods stuck in PENDING status during traffic spikes
*   **Symptoms**: Scale-up is triggered but new pods remain in `PENDING` state for several minutes, failing to handle the incoming request load.
*   **Diagnostics Command**:
    ```bash
    # Describe pending pod to read scheduler events
    kubectl describe pod <pending-pod-name> | tail -n 15
    ```
*   **Expected Event**: `0/5 nodes are available: 5 Insufficient cpu.`
*   **Root Cause**: The node autoscaler (Karpenter or Cluster Autoscaler) is too slow to spin up new VMs, or the cloud provider ran out of the requested instance sizes in the zone.
*   **Resolution**: Establish **Cluster Overprovisioning** (buffer pods) to keep spare, pre-warmed nodes active.
*   **Prevention**: Set up low-priority pause pods as described in the [Autoscaling Playbook](../autoscaling/autoscaling-efficiency-playbook.md).
