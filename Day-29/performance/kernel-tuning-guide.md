# 🐧 Kubernetes Linux Kernel Tuning & Performance Engineering

This guide explains how to optimize underlying Linux kernel parameters (`sysctl`) on Kubernetes nodes to handle high-throughput, low-latency applications (e.g., APIs, databases, message brokers).

---

## 1. Why Tune the Node Kernel?

Standard Linux distributions ship with default kernel configurations designed for general-purpose workloads. When running containerized microservices in high-density environments, these defaults frequently lead to performance bottlenecks, dropped connections, or TCP socket starvation under heavy load.

Because containers share the node's OS kernel, **tuning the node kernel optimizes performance for all running pods on that node**.

---

## 2. Core Kernel Parameters (`sysctl`) Explained

Here are the key network, filesystem, and memory sysctl options that must be tuned for production Kubernetes nodes.

### A. Connection Backlog Limits
If an application is receiving connections faster than it can process them, TCP packets are dropped, leading to client connection timeouts.

*   `net.core.somaxconn` (Default: `128` or `4096` on modern OS):
    *   **What it is**: The maximum queue length of pending connections (backlog) in the listen state.
    *   **Production Value**: `32768` (Allows applications to queue connections during traffic spikes).
*   `net.core.netdev_max_backlog` (Default: `1000`):
    *   **What it is**: The maximum number of packets allowed in the kernel network device queue before being processed by the CPU.
    *   **Production Value**: `16384` (Prevents packet drops at the NIC driver layer under high network traffic).

### B. TCP Window and Socket Buffers
These parameters dictate how much TCP buffer memory can be allocated per socket. Proper tuning allows high-throughput TCP connections to utilize the full available network bandwidth.

*   `net.ipv4.tcp_rmem` (Default: `4096 87380 6291456`):
    *   **What it is**: Min, default, and max TCP receive buffer sizes in bytes.
    *   **Production Value**: `4096 87380 16777216` (Allows receive windows to scale up to 16MB for high Bandwidth-Delay Product paths).
*   `net.ipv4.tcp_wmem` (Default: `4096 16384 4194304`):
    *   **What it is**: Min, default, and max TCP write/send buffer sizes in bytes.
    *   **Production Value**: `4096 65536 16777216` (Enables high throughput outbound sends).

### C. Socket Reuse and TCP Congestion Control
*   `net.ipv4.tcp_tw_reuse` (Default: `2`):
    *   **What it is**: Allows the kernel to safely reuse `TIME_WAIT` sockets for new connections, reducing connection startup overhead and port exhaustion.
    *   **Production Value**: `1`.
*   `net.core.default_qdisc` & `net.ipv4.tcp_congestion_control` (Default: `cubic`):
    *   **What it is**: The active queuing discipline and TCP congestion control algorithm.
    *   **Production Value**: `fq` and `bbr` (BBR drastically improves throughput and reduces latency under network packet loss).

---

## 3. How to Apply Kernel Optimizations in Kubernetes

There are three main patterns to apply these settings.

### Pattern 1: Node Initialization Scripts (Recommended for Cloud Provider Node Groups)
Configure sysctls during node bootstrapping via Cloud Init (AWS Launch Templates / GCP Instance Templates).

For AWS EKS (Bottlerocket OS), configure sysctls via user-data:
```toml
[settings.kernel.sysctl]
"net.core.somaxconn" = "32768"
"net.core.netdev_max_backlog" = "16384"
"fs.file-max" = "2097152"
```

### Pattern 2: Privileged DaemonSet (Used for existing running clusters)
Deploy a DaemonSet that runs an `initContainer` with root permissions to update settings. See [sysctl-tuned-daemonset.yaml](../manifests/sysctl-tuned-daemonset.yaml).

### Pattern 3: Pod-Level Sysctls (Safe Sysctls)
Kubernetes allows some sysctls to be set directly in the Pod Spec under `securityContext.sysctls`. Only "safe" namespaced sysctls are allowed by default (e.g., `net.ipv4.ping_group_range`).
"Unsafe" sysctls must be explicitly enabled on the kubelet configuration via `--allowed-unsafe-sysctls`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tuned-api-pod
spec:
  securityContext:
    sysctls:
    - name: net.core.somaxconn
      value: "8192" # Requires kubelet --allowed-unsafe-sysctls=net.core.somaxconn
  containers:
  - name: web
    image: nginx
```
