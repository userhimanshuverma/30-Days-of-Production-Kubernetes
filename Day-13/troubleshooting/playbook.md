# 🚨 Day 13 Troubleshooting Playbook: Autoscaling Failures

This runbook provides step-by-step diagnostic procedures and remediation steps for common Kubernetes autoscaling outages and configuration bugs.

---

## Playbook 1: HPA Not Scaling (Metrics Unavailable or Failing)

### Symptoms
* Command `kubectl get hpa` shows `<unknown>` under the `TARGETS` column.
* HPA events show `FailedGetResourceMetric` or `FailedComputeMetricsReplicas`.

### Root Cause Analysis
1. **Missing Resource Requests:** The HPA calculates scaling based on the percentage of **requested** resources. If the target Deployment's pod template lacks a `resources.requests.cpu` or `resources.requests.memory` definition, the HPA controller cannot calculate the percentage ratio.
2. **Metrics API Aggregation Failure:** The API Server cannot communicate with the `metrics-server` pod.
3. **Network Policies:** Ingress/egress rules are blocking the control plane from scraping `/stats/summary` ports on the worker nodes.

### Diagnostic & Resolution Steps

1. **Verify Workload Requests:**
   Ensure the target deployment has resource requests defined:
   ```bash
   kubectl get deployment dynamic-api-service -o jsonpath='{.spec.template.spec.containers[*].resources}'
   ```
   *If empty, edit the deployment and configure resource requests.*

2. **Verify Metrics API Service:**
   Check the APIService registration state:
   ```bash
   kubectl get apiservice v1beta1.metrics.k8s.io
   ```
   *Expect: `AVAILABLE` should be `True`.*
   
   If `False` or missing, describe the service:
   ```bash
   kubectl describe apiservice v1beta1.metrics.k8s.io
   ```

3. **Check Metrics Server Pod Logs:**
   If the APIService is failing, inspect the logs of the metrics-server pod in the `kube-system` namespace:
   ```bash
   kubectl logs -n kube-system -l k8s-app=metrics-server --tail=50
   ```
   *Common Error: `x509: certificate signed by unknown authority`.*
   *Solution:* If running in a local lab, ensure the `--kubelet-insecure-tls` flag is added to the metrics-server command arguments (see `manifests/metrics-server.yaml`).

---

## Playbook 2: Cluster Autoscaler Not Adding Nodes

### Symptoms
* Pods remain in `Pending` state indefinitely.
* Kube-scheduler shows `FailedScheduling` ("0/3 nodes are available: 3 Insufficient cpu").
* Cluster Autoscaler does not request new instances from the cloud provider.

### Root Cause Analysis
1. **Cloud Provider Limits Reached:** The Auto Scaling Group (ASG) or Managed Instance Group (MIG) has reached its configured `MaxSize` ceiling.
2. **Missing CA IAM Permissions:** The Cluster Autoscaler pod lacks the cloud IAM roles/permissions to modify ASG capacities.
3. **Unmatched Taints/Selectors:** The pending pods have node selectors, node affinity rules, or taints/tolerations that do not match the instance templates defined in the ASG.

### Diagnostic & Resolution Steps

1. **Check CA Logs for Decisions:**
   Query the Cluster Autoscaler logs to check its simulation output:
   ```bash
   kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100 | grep -i scale-up
   ```
   *Look for statements like: `Scale-up not triggerable`, `ASG size limit reached`, or `IAM credentials deny access`.*

2. **Inspect the ConfigMap Status:**
   Read the Cluster Autoscaler's status report stored in the cluster ConfigMap:
   ```bash
   kubectl get configmap cluster-autoscaler-status -n kube-system -o yaml
   ```
   *Analyze the `ReadableStatus` block to see if node groups are healthy, scale-up is blocked, or if any node groups are in backoff state.*

3. **Verify Node Group Max Size:**
   Check the maximum limits on the ASG/MIG via your cloud console or CLI. Ensure it matches the CA's target settings.

---

## Playbook 3: Pods Stuck Pending After Scaling (Scheduling Blocks)

### Symptoms
* Cluster Autoscaler successfully provisions new nodes.
* Pods still refuse to schedule, remaining `Pending` on the new nodes.

### Root Cause Analysis
1. **Pod Disruption Budgets (PDB):** Misconfigured PDBs are blocking eviction or reallocation.
2. **Missing Tolerations:** New nodes have auto-applied cloud taints (e.g. `node.cloudprovider.kubernetes.io/uninitialized:NoSchedule` or Karpenter startup taints) that are not tolerated by the pods.
3. **Volume Binding Mode:** The pod requires a Persistent Volume (PV) bound to a specific availability zone (AZ). The new nodes were provisioned in a different zone.

### Diagnostic & Resolution Steps

1. **Describe the Pending Pod:**
   Retrieve the scheduler's exact placement failure reason:
   ```bash
   kubectl describe pod <pending-pod-name>
   ```
   *Look at the `Events` section for volume binding or taint matching errors.*

2. **Verify PV Zone Matches Node Zone:**
   Check if the pod uses a PV:
   ```bash
   kubectl get pv -o custom-columns=NAME:.metadata.name,ZONE:.metadata.labels.topology\.kubernetes\.io/zone
   ```
   Compare this against the new node's availability zone:
   ```bash
   kubectl get nodes --show-labels | grep topology.kubernetes.io/zone
   ```
   *If the zones do not match, the scheduler cannot schedule the pod to the node.*

---

## Playbook 4: Scaling Thrashing (Oscillations)

### Symptoms
* Workload replicas oscillate rapidly (e.g. scales 3 -> 15 -> 3 -> 15) within minutes.
* Application logs show connection resets and high restart rates.

### Root Cause Analysis
* The scale-down stabilization window is too short. Immediately after scaling down due to a brief dip in traffic, the remaining pods are overwhelmed, causing utilization to spike and trigger a scale-up.

### Resolution
* Increase the `stabilizationWindowSeconds` inside the HPA spec's `scaleDown` block to `300` (5 minutes) or `600` (10 minutes). This forces the controller to wait and ensure the traffic drop is sustained before terminating replicas (see `manifests/hpa-cpu-memory.yaml`).
