# 📖 Day-19: Core Debugging Concepts & Kernel Mechanics

In a production Kubernetes cluster, workloads do not run in isolated virtual machines; they run as containerized processes sharing the host operating system's kernel. Consequently, debugging container failures requires a solid understanding of both **Kubernetes control plane abstractions** and the underlying **Linux kernel subsystems** that govern memory, CPU, and networking.

This guide provides the deep technical theory behind how containers crash, run out of memory, resolve names, and route network packets.

---

## 1. Container Lifecycle & Exit Codes: Linux Kernel Perspective

When a pod enters a `Failed` or `CrashLoopBackOff` state, it means the containerized process terminated. The `exit code` returned by the container is the single most valuable piece of initial evidence.

### Exit Code Ranges and Meanings
The kernel records exit codes as an 8-bit unsigned integer (0-255). By convention, specific ranges indicate distinct categories of termination:

| Exit Code | Signal / Convention | Description | SRE Investigation Path |
| :--- | :--- | :--- | :--- |
| **0** | Success | Process finished its task normally. | Check if a long-running daemon was run as a short-lived job, or if liveness probes caused a restart loop. |
| **1** | SIGHUP / Catchall | Application error or runtime panic (e.g., Python `IndexError`, Java `NullPointerException`). | Inspect stdout/stderr logs. |
| **2** | Misuse of Shell | Bash command syntax error or invalid configuration flag. | Check `command` or `args` fields in the Pod manifest. |
| **126** | Command invoked cannot execute | Permission mismatch or command is not an executable file. | Check file permissions and image build structure. |
| **127** | Command not found | The entrypoint binary or command path does not exist inside the image filesystem. | Verify path spelling or if a multi-stage build stripped the binary. |
| **137** | `SIGKILL` (128 + 9) | The process was abruptly terminated by the OS kernel. | Check cgroup memory limit settings (OOMKilled) or node-level eviction events. |
| **139** | `SIGSEGV` (128 + 11) | Segmentation fault. Attempt to access unallocated memory address (often C/C++ or native Node/Python bindings). | Check memory safety, native driver versions, and run a debugger profile. |
| **143** | `SIGTERM` (128 + 15) | Graceful termination signal. The container was told to exit. | Check if the deployment was scaled down, or if the Pod was evicted/rescheduled. |

---

## 2. Memory Limits & OOMKilled (Exit Code 137)

Understanding the Out-Of-Memory (OOM) killer requires diving into Linux kernel **control groups (cgroups)** and the **OOM score calculation**.

### Cgroups v1 vs v2 Memory Limits
Kubernetes uses Linux cgroups to enforce memory limits:
*   **Requests:** Maps to `memory.soft_limit_in_bytes` (cgroups v1) or `memory.low/memory.high` (cgroups v2). The kernel uses this value during memory reclamation under resource pressure.
*   **Limits:** Maps directly to `memory.limit_in_bytes` (cgroups v1) or `memory.max` (cgroups v2). If a container's memory resident set size (RSS) attempts to cross this value, the kernel refuses the allocation.

### The Kernel OOM Killer Workflow
When the kernel runs low on memory, it calls the `oom_killer` subsystem. 
1.  **OOM Score Calculation:** Every process is assigned an `oom_score` (ranging from 0 to 1000). The higher the score, the more likely the process is to be killed.
    
    $$\text{oom\_score} \propto \text{Percent of Memory Consumed} + \text{oom\_score\_adj}$$
    
2.  **OOM Score Adjustments in K8s:** Kubernetes sets `oom_score_adj` based on the Pod's Quality of Service (QoS) class:
    *   **Guaranteed** (Limits == Requests): `oom_score_adj = -997` (Highly protected; almost never killed unless host is dying).
    *   **Burstable** (Limits > Requests): Adjusted dynamically based on requests relative to node size:
        
        $$\text{oom\_score\_adj} = 1000 - \max\left(\left( \frac{\text{memory\_request}}{\text{node\_memory}} \times 1000 \right), 2\right)$$
        
    *   **BestEffort** (No limits, no requests): `oom_score_adj = 1000` (First to be terminated).

3.  **The Kill:** The process with the highest score is sent a `SIGKILL` (Exit Code 137). The Kubelet detects this termination state from the container runtime, sets `OOMKilled: true` in the pod status, and schedules a restart based on the restart policy.

---

## 3. Kubernetes Network Routing Deep Dive

When debugging connectivity, SREs must trace packets through **kube-proxy rules**, **iptables/IPVS chains**, and **CNI overlays**.

### Kube-Proxy Modes: Iptables vs. IPVS
`kube-proxy` is responsible for implementing the cluster-wide IP virtual service network for `Services`.

```
[Client Pod] ➔ [iptables PREROUTING] ➔ [Random DNAT (Load Balancing)] ➔ [Target Pod IP]
```

#### Iptables Mode (Default)
For each Service, `kube-proxy` writes sequential rules using Netfilter iptables.
*   **PREROUTING / OUTPUT:** Intercepts traffic to the Service's ClusterIP.
*   **KUBE-SERVICES:** Routes traffic to service-specific chains.
*   **KUBE-SVC-XXX:** Dynamically load-balances traffic using the `statistic` module with random probabilities:
    *   If a service has 3 backend pods: Pod 1 has $33\%$ probability, Pod 2 has $50\%$ probability of remaining traffic, Pod 3 has $100\%$ probability of remaining traffic.
*   **Drawback:** O(N) lookup complexity. If a cluster has 10,000 services, the iptables rule list becomes massive, causing significant CPU overhead and packet routing latency.

#### IPVS Mode (IP Virtual Server)
Uses Netfilter's transport-layer load balancing implemented inside the Linux kernel.
*   Uses a hash table structure.
*   **Complexity:** O(1) lookup speed, regardless of cluster scale.
*   Supports multiple load-balancing algorithms (round-robin, least-connections, shortest-expected-delay).

---

## 4. DNS Resolution & Service Discovery (resolv.conf & ndots)

DNS is the most common source of "networking" failures in production. To understand why DNS queries fail or take too long, we must dissect `/etc/resolv.conf` inside a Pod.

### Inside `/etc/resolv.conf`
A default Kubernetes pod contains resolver configurations resembling the following:
```text
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

*   **nameserver:** Points to the ClusterIP of the `kube-dns` / `CoreDNS` service.
*   **search:** The search suffixes appended to non-fully-qualified domain queries.
*   **ndots:5:** The core mechanism governing search path lookup.

### The `ndots` Trap
The `ndots` option defines the minimum number of periods (`.`) a domain name must contain before the resolver attempts a direct query without appending search paths first.
*   If `ndots:5` (Kubernetes default), and the app queries `api.stripe.com` (which contains 2 dots):
    1.  Resolver checks: `api.stripe.com.default.svc.cluster.local` ➔ CoreDNS returns `NXDOMAIN` (Name Error).
    2.  Resolver checks: `api.stripe.com.svc.cluster.local` ➔ CoreDNS returns `NXDOMAIN`.
    3.  Resolver checks: `api.stripe.com.cluster.local` ➔ CoreDNS returns `NXDOMAIN`.
    4.  Resolver checks: `api.stripe.com` ➔ CoreDNS forwards to upstream resolver ➔ Returns IP (Success).
*   **Performance Impact:** Every external domain lookup generates **4 DNS queries** (3 failures, 1 success), adding unnecessary latency and placing huge request loads on CoreDNS.
*   **SRE Fix:** Append a trailing dot to the domain in application configurations (e.g. `api.stripe.com.`), which bypasses the search path loop entirely, or customize `dnsConfig` in the Pod spec.

---

*Proceed to the [production-notes/](../production-notes/) folder to review senior-level operating practices, escalation runbooks, and MTTR reduction strategies.*
