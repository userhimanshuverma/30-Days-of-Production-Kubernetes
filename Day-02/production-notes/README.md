# ⚡ Day 02 Production Notes: Container Security, Starvation, and Runtime Realities

In large-scale production Kubernetes environments, container abstractions reveal their underlying operating system dependencies. These notes provide senior-level engineering insights gathered from running millions of containers in production.

---

## 1. Shared Kernel Risks & Security Realities

Because containers share the host kernel, they do not possess a true security boundary like a hypervisor. If a process escapes its container boundaries, it gains direct access to the host kernel APIs.

### The Attack Surface
*   **Kernel Exploits:** If an application inside a container exploits a local privilege escalation bug in the host kernel (e.g., Dirty COW, CVE-2022-0847 Dirty Pipe), it immediately compromises the host OS and all other containers running on that node.
*   **System Calls:** A standard Linux kernel has over 300 system calls. A default container running as root (even without `--privileged`) has access to most of them. Attackers can leverage obscure syscalls to bypass namespaces.
*   **Production Mitigation:**
    *   **Disable Privilege Escalation:** Always set `allowPrivilegeEscalation: false` in your Pod spec.
    *   **Enforce Seccomp Profiles:** SECure COMPuting (seccomp) restricts the syscalls a process can make. Enforcing the `RuntimeDefault` seccomp profile drops over 100 dangerous syscalls (like `sys_ptrace`, `sys_reboot`, `sys_syslog`).
    *   **Use Sandboxed Runtimes:** For untrusted or multi-tenant code execution, bypass standard runc. Use:
        *   **gVisor (runsc):** Intercepts system calls in user space using a guest kernel written in Go (Sentry), preventing direct host kernel access.
        *   **Kata Containers:** Runs containers inside lightweight, fast-booting virtual machines (MicroVMs) utilizing QEMU or Firecracker.

---

## 2. Resource Starvation: Compressible vs. Incompressible Resources

Kubernetes manages two main resource types, and the kernel handles their exhaustion in fundamentally different ways.

```
                  +---------------------------------------+
                  |           Resource Overuse            |
                  +---------------------------------------+
                                      |
                 +--------------------+--------------------+
                 |                                         |
     (Compressible: CPU)                       (Incompressible: Memory)
                 |                                         |
                 v                                         v
   +---------------------------+             +---------------------------+
   |  Kernel Throttles Cycles  |             |  Kernel Invokes OOM Killer|
   |      (CFS Scheduler)      |             |     (Kills Process)       |
   +---------------------------+             +---------------------------+
   |   App slows down;         |             |   App crashes instantly   |
   |   Latency spikes.         |             |      (Exit Code 137)      |
   +---------------------------+             +---------------------------+
```

### CPU (Compressible)
*   **Kernel Mechanism:** Completely Fair Scheduler (CFS) bandwidth control.
*   **Overuse Outcome:** Throttling. If a container exceeds its CPU limit within a cgroup period (usually 100ms), the kernel halts the execution of its processes until the next period.
*   **Production Impact:** Latency spikes, timeout errors, and queue build-up. The container does **not** crash.
*   **Production Tip:** High-concurrency apps (like Java Spring or Node.js) often suffer from CFS throttling even when their average CPU usage is far below the limit. This occurs due to micro-bursts that deplete the 100ms quota within the first few milliseconds. Many organizations run without CPU limits (`resources.limits.cpu` unset) and rely strictly on `resources.requests.cpu` and CPU shares to avoid latency spikes.

### Memory (Incompressible)
*   **Kernel Mechanism:** Out-of-Memory (OOM) Killer.
*   **Overuse Outcome:** Termination. Memory cannot be throttled or queued. If a container allocates memory beyond its configured limit, the kernel terminates the process (`OOMKilled`, Exit Code 137).
*   **Production Impact:** Instant crash, service disruption, and potential cascading failures as traffic shifts to surviving pods.
*   **Kernel Tuning (`oom_score_adj`):** The kernel assigns an `oom_score` to processes to decide which to kill when the host is low on memory. Kubernetes automatically adjusts this score based on the Pod's Quality of Service (QoS) class:
    *   **Guaranteed Pods:** `oom_score_adj = -997` (Extremely unlikely to be killed by host OOM).
    *   **Burstable Pods:** `oom_score_adj = 2 to 999` (Moderately likely).
    *   **BestEffort Pods:** `oom_score_adj = 1000` (First to be terminated when host memory is exhausted).

---

## 3. The "Noisy Neighbor" Problem: Under-Isolated Host Resources

Namespaces do not isolate every system resource. Several global host resources can be depleted by a single container, impacting all pods on the node:
1.  **Disk I/O (IOPS):** Standard Kubernetes limits do not restrict read/write operations per second. A container writing heavy logs or temp files can saturate the host disk queue, blocking database containers.
    *   *Mitigation:* Configure storage classes with IOPS limits or use cgroups v2 writeback throttling.
2.  **Kernel Entropy:** Cryptographic operations require system entropy (randomness). A pod consuming entropy rapidly can stall other pods waiting for `/dev/random`.
3.  **Process IDs (PID Exhaustion / Fork Bomb):** The Linux kernel has a global limit of process IDs (`cat /proc/sys/kernel/pid_max`). A compromised or poorly written app that spawns threads in an infinite loop can consume all host PIDs.
    *   *Mitigation:* Enable the `SupportPodPidsLimit` feature gate in Kubelet and set container-level PID limits using cgroups.
4.  **Conntrack Table Exhaustion:** The Linux network connection tracking table (`nf_conntrack`) holds records of all active connections. A pod performing high-frequency outbound requests can saturate this table, preventing the entire node from establishing any new network connections.

---

## 4. Container Networking Overhead

In production, container network interfaces (`veth` pairs) create packet forwarding overhead.
*   **The Path of a Packet:**
    1.  Container app sends packet to `eth0` (virtual).
    2.  Packet is redirected through the virtual ethernet tunnel (`veth` pair) to the host namespace.
    3.  Host kernel processes the packet, passing it through `iptables` or IPVS rules (Kubernetes Services).
    4.  Packet is routed to the physical network card (`eth0` on the host).
*   **Overhead:** This context-switching and routing between namespaces introduces latency (typically 5-15% throughput drop compared to bare-metal host network speeds).
*   **High Performance Tuning:** For low-latency workloads (e.g. trading platforms, databases), use **eBPF-based networking (Cilium CNI)**. Cilium utilizes eBPF programs to bypass the host TCP/IP stack and redirect packets directly from the container's virtual network interface socket to the physical network interface or target container socket, cutting out namespace routing overhead completely.
