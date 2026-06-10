# 🛠️ Kubernetes Production Troubleshooting Runbooks

This playbook contains step-by-step diagnostic workflows for the 10 most common failures encountered when operating workloads in production.

---

## 1. CrashLoopBackOff (Startup Failure)
*The pod continuously restarts, crashing immediately after startup.*

### Symptoms
*   `kubectl get pods` shows status `CrashLoopBackOff` or `Error`.
*   Pod restarts count increments rapidly.

### Investigation
1.  **Check previous logs:**
    ```bash
    kubectl logs <pod-name> --previous
    ```
2.  **Describe Pod details:**
    ```bash
    kubectl describe pod <pod-name>
    ```
    Look at the `Last State` exit code and the `Events` section at the bottom.

### Root Cause
Common issues include missing environment variables, configuration syntax errors, database/dependency unreachable, or directory permissions mismatch.

### Resolution
*   If configuration is missing, update the corresponding `ConfigMap` or `Secret` and force-restart the pod:
    ```bash
    kubectl rollout restart deployment/<deployment-name>
    ```
*   If a dependency is offline, restore the dependency first.

### Prevention
*   Implement startup delay checks and robust connection-retry loops with exponential backoff inside the application code.
*   Use schema validators for environment variable parsing.

---

## 2. OOMKilled (Exit Code 137)
*The container process is terminated by the host kernel for exceeding memory thresholds.*

### Symptoms
*   `kubectl describe pod` displays `OOMKilled: true` and `Exit Code: 137` in the container state.

### Investigation
1.  **Check memory usage trends:**
    ```bash
    kubectl top pod <pod-name>
    ```
2.  **Inspect container limits:**
    Look for `Limits.memory` in the describe output.
3.  **Review Node Kernel logs:**
    If the host kernel killed the process without Kubelet evicting it, inspect `/var/log/messages` or running `dmesg -T | grep -i oom` on the node.

### Root Cause
The containerized application is allocating memory beyond its defined cgroup limits (e.g., due to memory leaks, loading large objects in RAM, or under-provisioned limits).

### Resolution
*   Apply a hotfix to increase the memory limit in the deployment manifest:
    ```bash
    kubectl patch deployment <deploy> --patch '{"spec":{"template":{"spec":{"containers":[{"name":"<name>","resources":{"limits":{"memory":"512Mi"}}}]}}}}'
    ```

### Prevention
*   Establish Prometheus alerts for `container_memory_working_set_bytes` approaching limits.
*   Profile application memory allocation in staging before production deploy.

---

## 3. Failed DNS Lookups
*Pods are unable to resolve external domains or cluster-local services.*

### Symptoms
*   Application logs show `Host not found`, `dial tcp: lookup...` or `Temporary failure in name resolution`.

### Investigation
1.  **Test resolution from inside the pod:**
    ```bash
    kubectl exec -it <pod-name> -- nslookup order-service
    ```
2.  **Inspect `/etc/resolv.conf`:**
    ```bash
    kubectl exec -it <pod-name> -- cat /etc/resolv.conf
    ```
    Verify if the `nameserver` matches the CoreDNS service ClusterIP.

### Root Cause
Can occur due to overridden DNS settings in the pod's `dnsPolicy`, upstream DNS forwarding issues, or CoreDNS scaling bottlenecks.

### Resolution
*   Correct the `dnsPolicy` to `ClusterFirst` (default) in the Pod spec.
*   Add a trailing dot (e.g., `api.stripe.com.`) in application properties to bypass search path performance degradation.

### Prevention
*   Configure a Node-Local DNS Cache (`NodeLocal DNSCache`) to intercept DNS queries on the host node, avoiding round-trips to CoreDNS.

---

## 4. Service Unreachable (503 / Connection Refused)
*Client pods get connection refused when sending requests to a Service ClusterIP.*

### Symptoms
*   HTTP calls to the service address return `503 Service Unavailable` or `Connection Refused`.

### Investigation
1.  **Check Service Endpoints:**
    ```bash
    kubectl get endpoints <service-name>
    ```
    Verify if the `ENDPOINTS` column lists any IP addresses.
2.  **Verify Pod labels:**
    Compare the service selector labels with the running pod labels:
    ```bash
    kubectl get pods --show-labels
    ```

### Root Cause
Mismatched label selectors between the service and deployment, container port mismatches, or unhealthy pods failing readiness probes.

### Resolution
*   Align the service `.spec.selector` labels with the pod's `.metadata.labels`.
*   Verify the service `.spec.ports[].targetPort` matches the container's `.spec.containers[].ports[].containerPort`.

### Prevention
*   Ensure CI linting checks (like `kube-linter` or `Kubeval`) validate selector pairings.

---

## 5. CoreDNS Scaling & Failure
*DNS requests fail globally or experience high latency.*

### Symptoms
*   Widespread DNS lookup failures across multiple namespaces.
*   CoreDNS pod logs show warnings or timeouts.

### Investigation
1.  **Inspect CoreDNS logs:**
    ```bash
    kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100
    ```
2.  **Check CoreDNS CPU/Memory usage:**
    ```bash
    kubectl top pods -n kube-system -l k8s-app=kube-dns
    ```

### Root Cause
CoreDNS is resource-starved under high traffic load, or upstream DNS nameservers are failing.

### Resolution
*   Autoscale CoreDNS using horizontal pod autoscaler (HPA) or cluster-proportional-autoscaler.
*   Increase resource requests/limits on CoreDNS deployment:
    ```bash
    kubectl edit deployment coredns -n kube-system
    ```

### Prevention
*   Always define reasonable CPU and Memory requests for CoreDNS pods to prevent them from being throttled or OOMKilled.

---

## 6. Resource Starvation (Throttling)
*The application response latency increases, and processing becomes sluggish.*

### Symptoms
*   High latency metrics.
*   CPU limits are hit, but the pod does not crash.

### Investigation
1.  **Check CPU Throttling metrics:**
    Query Prometheus for:
    ```promql
    container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total
    ```
2.  **Inspect pod CPU utilization:**
    ```bash
    kubectl top pod <pod-name>
    ```

### Root Cause
The CPU limits configured in the pod resource spec are set too low, causing the CFS scheduler to throttle execution times.

### Resolution
*   Increase or remove CPU limits (leaving only requests) if using a cluster that relies solely on CPU shares for throttling mitigation.

### Prevention
*   Establish alerts for CPU throttling percentage exceeding 10% over a 5-minute window.

---

## 7. Pending Pods (Scheduler Block)
*Pods are created but remain in a `Pending` state indefinitely.*

### Symptoms
*   `kubectl get pods` shows status `Pending`.

### Investigation
1.  **Inspect Events:**
    ```bash
    kubectl describe pod <pod-name>
    ```
    Read the messages at the bottom under the `Events` section. Look for `FailedScheduling`.

### Root Cause
Insufficient resources (CPU/Memory) in the cluster, node selector or affinity rules matching zero nodes, node taints without matching tolerations, or PVC mounting failures.

### Resolution
*   If resource-constrained, scale your worker nodes (autoscaler) or lower the pod's resource requests.
*   Correct node selector labels or pod anti-affinity parameters.

### Prevention
*   Set up cluster autoscalers to automatically add nodes when pods fail to schedule due to resource issues.

---

## 8. Node Failure & NotReady State
*Pods are evicted or fail because their host Node enters a `NotReady` state.*

### Symptoms
*   `kubectl get nodes` shows node status `NotReady`.
*   Pods on that node transition to `Unknown` or `Terminating`.

### Investigation
1.  **Describe the Node:**
    ```bash
    kubectl describe node <node-name>
    ```
    Look at the `Conditions` section (e.g., `MemoryPressure`, `DiskPressure`, `PIDPressure`).
2.  **SSH and check kubelet service logs:**
    ```bash
    journalctl -u kubelet -n 100
    ```

### Root Cause
Kubelet process crashed, disk is full (out of ephemeral storage), node memory exhaustion, or network separation from the control plane.

### Resolution
*   If disk is full, clean up untagged docker images or logs under `/var/log/`.
*   Evacuate remaining pods safely:
    ```bash
    kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
    ```

### Prevention
*   Enforce disk reclamation policies on the kubelet.
*   Monitor node CPU, Memory, and Disk metrics.

---

## 9. Broken Ingress Routing
*Requests to external URLs return 404 Not Found or 502 Bad Gateway.*

### Symptoms
*   External API/Web requests return `HTTP 404` or `502 Bad Gateway`.

### Investigation
1.  **Check Ingress resource rules:**
    ```bash
    kubectl get ingress
    ```
    Verify the `HOSTS` and `ADDRESS` fields.
2.  **Inspect Ingress Controller logs:**
    ```bash
    kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
    ```

### Root Cause
Typo in the ingress host name, bad target service name, or the backend service target port is mismatched.

### Resolution
*   Match backend service name and ports inside the `ingress.yaml` file with the actual running Service definitions.
*   Update the ingress controller ConfigMap to reload configuration.

### Prevention
*   Use validation webhooks to reject invalid ingress manifests before they get applied to the cluster API.

---

## 10. Application Startup Failures (InitContainers)
*The main container never starts because the init-container crashes.*

### Symptoms
*   Pod status shows `Init:CrashLoopBackOff` or `Init:0/1`.

### Investigation
1.  **View Init Container logs:**
    ```bash
    kubectl logs <pod-name> -c <init-container-name>
    ```
2.  **Describe Pod details:**
    ```bash
    kubectl describe pod <pod-name>
    ```

### Root Cause
The init-container (often running a script checking for migrations or dependent ports) failed its check, ran out of memory, or timed out.

### Resolution
*   Fix the service/port configuration check in the init-container commands.
*   Lower init-container resource limits if it is getting OOMKilled.

### Prevention
*   Wrap init-container dependencies with timeout exits (e.g. `timeout 30s nc -z ...`), avoiding indefinite lockups.
