# Kubernetes & Platform Engineering Glossary

A reference index of core architectural concepts and terminology used throughout this course.

---

## 🏛️ Architecture & Interfaces
*   **CRI (Container Runtime Interface)**: The gRPC API specification that enables the kubelet to communicate with various container runtimes (e.g., `containerd`, `CRI-O`) without recompiling the core code.
*   **CNI (Container Network Interface)**: The standard interface that dictates how network plugins (e.g., `Calico`, `Cilium`) configure IP addresses, network boundaries, and packet routing for pods.
*   **CSI (Container Storage Interface)**: The dynamic interface that allows storage vendors (e.g., AWS EBS, Ceph) to attach, format, and mount persistent disks out-of-tree.
*   **Control Plane**: The central brain of the cluster, responsible for keeping the cluster state in consensus, scheduling workloads, and handling events. It comprises the API Server, etcd, Controller Manager, and Scheduler.
*   **etcd**: A strongly consistent, distributed key-value database used as the single source of truth for all Kubernetes cluster state metadata.

---

## 📦 Resource Abstractions
*   **Pod**: The smallest deployable computing unit in Kubernetes, wrapping one or more containers that share network interfaces and storage namespaces.
*   **DaemonSet**: A workload controller that guarantees a single copy of a pod runs on all (or selected) nodes in the cluster (e.g., log shippers, monitoring agents).
*   **StatefulSet**: A workload controller used to run stateful applications, providing guarantees about unique network identifiers, sequential scaling, and persistent disk bindings.
*   **Ingress**: An API object that manages external HTTP/S routing access to services inside the cluster, typically fronted by an Ingress Controller (like NGINX).
*   **StorageClass**: A resource template that allows SREs to define the storage backend, reclaim policy, and dynamic volume binding rules.

---

## ⚙️ Operations & Optimization
*   **HPA (Horizontal Pod Autoscaler)**: Automatically scales the number of pods in a deployment up or down based on resource utilization (CPU/Memory) or custom external metrics.
*   **VPA (Vertical Pod Autoscaler)**: Observes container CPU and memory consumption and suggests (or applies) optimal resource request/limit sizes.
*   **Karpenter**: A cost-optimized Kubernetes node auto-provisioner that observes pending pods, calculates compute requirements, and provisions nodes directly using cloud APIs.
*   **OOMKill (Exit Code 137)**: The action taken by the Linux kernel's Out-Of-Memory Killer when a container exceeds its cgroup memory limit, terminating the process to protect host stability.
*   **CFS Throttling (Completely Fair Scheduler)**: The kernel mechanism that restricts a container's CPU consumption when it exceeds its CPU quota limits within a given period (100ms), causing response latency.
*   **Bin-Packing**: The scheduling optimization pattern of consolidating containers onto as few node hosts as possible to maximize utilization and reduce cluster costs.
