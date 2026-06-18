# 🚨 Production Outage Playbook: Kubernetes Architecture

This playbook provides step-by-step diagnostic workflows, investigation commands, and resolution plans for 10 common production-grade Kubernetes architectural failures.

---

## Scenario 1: Architecture Bottlenecks (API Server Saturation)
* **Symptoms:** `kubectl` requests timeout. Node statuses flap between `Ready` and `NotReady`. Deployments and scaling actions are delayed.
* **Root Cause:** A misconfigured custom controller or GitOps reconciler is running unbounded `list` queries across all namespaces without using pagination, saturating the API server's CPU and memory resources.
* **Investigation Commands:**
  ```bash
  # Check kube-apiserver CPU/Memory consumption
  kubectl top pods -n kube-system -l component=kube-apiserver
  
  # Check API Server request latency from Prometheus metrics
  # Query: histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket[5m])) by (le))
  ```
* **Resolution:**
  1. Identify the offending User-Agent from API server audit logs.
  2. Implement API Priority and Fairness (APF) rules to throttle the client:
     ```yaml
     apiVersion: flowcontrol.apiserver.k8s.io/v1beta3
     kind: FlowSchema
     metadata:
       name: throttle-noisy-controller
     spec:
       priorityLevelConfiguration:
         name: catch-all
       matchingRequests:
       - subjects:
         - kind: ServiceAccount
           serviceAccount:
             name: noisy-controller-sa
             namespace: monitoring
         rules:
         - resourceRules:
           - apiGroups: ["*"]
             resources: ["*"]
             verbs: ["*"]
     ```
* **Prevention:** Enforce API paging rules and use `FlowSchemas` to prevent unauthenticated clients or background tools from saturating control plane resources.

---

## Scenario 2: Traffic Congestion (Ingress Upstream Latency / Failures)
* **Symptoms:** External users receive HTTP 502/504 errors. Ingress controller logs show `upstream timed out (110: Connection timed out)`.
* **Root Cause:** The backend application pods are overloaded, failing their readiness health checks, or blocking threads, causing Nginx Ingress to drop backend endpoints from the active routing pool.
* **Investigation Commands:**
  ```bash
  # Inspect ingress logs for backend routing errors
  kubectl logs -n ingress-infra -l app.kubernetes.io/name=ingress-nginx --tail=200 | grep "upstream"
  
  # Check if backend endpoints exist
  kubectl get endpoints ecom-backend-svc -n production-app
  ```
* **Resolution:**
  1. Scale the backend deployment to handle the traffic load.
  2. Adjust ingress timeout settings:
     ```bash
     kubectl annotate ingress ecom-ingress -n production-app nginx.ingress.kubernetes.io/proxy-connect-timeout="15"
     kubectl annotate ingress ecom-ingress -n production-app nginx.ingress.kubernetes.io/proxy-read-timeout="60"
     ```
* **Prevention:** Configure Horizontal Pod Autoscalers (HPA) using request-per-second (RPS) metrics and implement backend circuit breakers in the service mesh to fail fast and prevent thread blockages.

---

## Scenario 3: Zone Failures (Split-Brain / Network Partitioning)
* **Symptoms:** Applications in Zone-A cannot talk to databases in Zone-B. Workloads fail to mount storage volumes. Control plane reports a partition.
* **Root Cause:** A physical network link failure or fiber cut between availability zones in the cloud region.
* **Investigation Commands:**
  ```bash
  # Check nodes in the cluster and identify their zones
  kubectl get nodes -L topology.kubernetes.io/zone
  
  # Check pod schedule errors related to volume zone lock
  kubectl get events -n production-app --sort-by='.metadata.creationTimestamp' | grep "volume"
  ```
* **Resolution:**
  1. For stateless applications, adjust replica distributions to schedule pods only in the healthy zones.
  2. If etcd loses its quorum node in the failed zone, run a force-reconfiguration on the remaining healthy control plane nodes.
* **Prevention:** Use `topologySpreadConstraints` with `whenUnsatisfiable: ScheduleAnyway` as a fallback, and utilize cross-zone replication databases (like CockroachDB).

---

## Scenario 4: Platform Outages (etcd Database Quota Exceeded)
* **Symptoms:** API Server rejects all write mutations with error `etcdserver: mvcc: database space exceeded`. Read operations still function.
* **Root Cause:** The etcd database size has exceeded its maximum allocated storage limit (typically 2GB or 8GB), caused by high object creation/deletion churn without running database compaction.
* **Investigation Commands:**
  ```bash
  # Check etcd endpoint metrics using etcdctl
  etcdctl --endpoints=https://127.0.0.1:2379 endpoint hash -w table
  etcdctl --endpoints=https://127.0.0.1:2379 endpoint status -w table
  ```
* **Resolution:**
  1. Trigger an etcd compaction to reclaim database space:
     ```bash
     # Get current revision number
     rev=$(etcdctl --endpoints=https://127.0.0.1:2379 endpoint status --write-out="json" | egrep -o '"revision":[0-9]*' | egrep -o '[0-9]*')
     # Compact to current revision
     etcdctl --endpoints=https://127.0.0.1:2379 compact $rev
     # Defragment storage
     etcdctl --endpoints=https://127.0.0.1:2379 defrag
     # Clear alarm
     etcdctl --endpoints=https://127.0.0.1:2379 alarm disarm
     ```
* **Prevention:** Enable auto-compaction flags (`--auto-compaction-retention=1`) on the API server and increase `--quota-backend-bytes` to 8GB for large enterprise environments.

---

## Scenario 5: Security Misconfigurations (NetworkPolicy DNS Blockage)
* **Symptoms:** Pods start up but fail to connect to external APIs or resolve database addresses. Application logs report `UnknownHostException` or `Temporary failure in name resolution`.
* **Root Cause:** A newly applied egress NetworkPolicy lacks rules allowing DNS queries (port 53 UDP/TCP) to the `kube-dns` service in the `kube-system` namespace.
* **Investigation Commands:**
  ```bash
  # Inspect NetworkPolicies applied in the namespace
  kubectl get netpol -n production-app
  
  # Query NetworkPolicy description details
  kubectl describe netpol secure-backend -n production-app
  ```
* **Resolution:** Add a DNS rule to the NetworkPolicy's egress block:
  ```yaml
  egress:
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
  ```
* **Prevention:** Use template-based NetworkPolicies that pre-approve outbound DNS resolution for all application tiers.

---

## Scenario 6: Scaling Issues (HPA Capacity Limits)
* **Symptoms:** HPA shows target CPU utilization is high, but replicas remain capped. Kubernetes events log `FailedScheduling: 0/15 nodes are available: Insufficient CPU`.
* **Root Cause:** The Kubernetes cluster autoscaler cannot scale up new worker nodes because the cloud provider account has hit its virtual machine quota or the NAT Gateway has run out of public IPs.
* **Investigation Commands:**
  ```bash
  # Check autoscaler status events
  kubectl get events -n kube-system | grep "Autoscaler"
  
  # Inspect cluster autoscaler configmap details
  kubectl describe configmap cluster-autoscaler-status -n kube-system
  ```
* **Resolution:**
  1. Increase the maximum node limit inside the Autoscaler's Auto Scaling Group (ASG) or Karpenter configuration.
  2. Request a VM CPU limit increase in the cloud provider console.
* **Prevention:** Run overprovisioning "Pause Pods" with low priority to reserve capacity, and configure automated alerts checking cloud account quota thresholds.

---

## Scenario 7: Resource Exhaustion (OOMKilled Cascades)
* **Symptoms:** Application pods terminate with status `OOMKilled`. As surviving pods pick up the remaining traffic, they exhaust their memory and crash as well, causing a cascading failure.
* **Root Cause:** Pods lack memory limits, or the limits are set too low to handle the traffic load, causing the host OS to terminate container processes to save node memory.
* **Investigation Commands:**
  ```bash
  # Check pod termination statuses
  kubectl get pods -n production-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[*].lastState.terminated.reason}{"\n"}{end}'
  ```
* **Resolution:**
  1. Scale up the deployment's memory limits to allocate more capacity to the container runtime.
  2. Temporarily scale down non-essential background workloads on the same nodes to free up memory.
* **Prevention:** Run load tests to determine peak-load memory requirements, enforce minimum memory limits using `LimitRanges`, and use vertical pod autoscalers (VPA) in recommendation mode to adjust limits.

---

## Scenario 8: Observability Gaps (Prometheus Disk Saturation)
* **Symptoms:** Grafana dashboards show empty charts. Prometheus logs write failures: `write: no space left on device`. Prometheus pod status enters `CrashLoopBackOff`.
* **Root Cause:** High cluster churn (e.g., thousands of batch jobs creating dynamic metric labels) has caused metric cardinality explosion, exhausting the local storage volume.
* **Investigation Commands:**
  ```bash
  # Check Prometheus persistent volume storage usage
  kubectl get pvc -n monitoring
  ```
* **Resolution:**
  1. Increase the PVC storage allocation size (if the storage class supports volume expansion).
  2. Shorten the metrics retention window using the Prometheus configuration argument `--storage.tsdb.retention.time=15d`.
* **Prevention:** Set up Thanos to offload metrics blocks to S3 object storage after two hours, and restrict application metric endpoints from generating high-cardinality labels.

---

## Scenario 9: Deployment Failures (PDB Blocking Drains)
* **Symptoms:** Cluster upgrades or node maintenance scripts hang. `kubectl drain` commands timeout with error: `Cannot evict pod as it would violate PodDisruptionBudget`.
* **Root Cause:** A `PodDisruptionBudget` is configured with `minAvailable: 2` or `maxUnavailable: 0` on a deployment that has only two running replicas, blocking the scheduler from evicting pods.
* **Investigation Commands:**
  ```bash
  # List all PDB boundaries
  kubectl get pdb -A
  
  # Check eviction blocking details
  kubectl get events -n production-app | grep "evict"
  ```
* **Resolution:**
  1. Temporarily increase the deployment's replica count to three so a pod can be safely drained without violating the PDB.
  2. If needed, temporarily delete the PDB manifest to complete the node drain.
* **Prevention:** Do not configure `minAvailable` matching the deployment's exact replica count. Use percentage values (`minAvailable: 50%`) instead of fixed numbers.

---

## Scenario 10: Production Incidents (IP Address Exhaustion)
* **Symptoms:** Pods hang in `ContainerCreating` status. Node logs report `Failed to allocate IP address: no addresses available`.
* **Root Cause:** The subnet hosting the worker nodes has run out of available private IP addresses, preventing the CNI from assigning IPs to new pods.
* **Investigation Commands:**
  ```bash
  # Check pod scheduling error details
  kubectl describe pod <pod-name> -n production-app
  ```
* **Resolution:**
  1. Add a secondary CIDR block to the VPC network.
  2. Configure the CNI (e.g., AWS-VPC-CNI custom networking) to assign pod IPs from the new subnet range.
* **Prevention:** Use overlay network CNIs (like Cilium in overlay mode) to decouple pod IP allocations from the physical VPC subnet CIDR blocks.
