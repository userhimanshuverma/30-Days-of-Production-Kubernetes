# 🛠️ Day 4 Hands-On Labs: Index & Overview
## 30 Days of Production Kubernetes — Day 4

In these labs, you will transition from theoretical understanding to hands-on command execution. You will create basic Pods, explore shared namespaces, deploy native sidecars, tune probe settings, and debug real container failures.

---

## 📋 Lab Directory

Each lab is self-contained and lists pre-requisites, manifests, and expected console outputs.

| Lab Number | Lab Title | Core Focus | Manifests | Estimated Time |
|---|---|---|---|---|
| **[Lab 1](lab-1-basic-pod.md)** | [Creating & Inspecting Basic Pods](lab-1-basic-pod.md) | Pod metadata, unprivileged containers, checking cgroup allocations on the node | `01-basic-pod.yaml` | 10 mins |
| **[Lab 2](lab-2-multi-container.md)** | [Multi-Container Shared Volume Operations](lab-2-multi-container.md) | Shared emptyDir volume, writing logs from one container and shipping from another | `02-shared-storage.yaml` | 15 mins |
| **[Lab 3](lab-3-init-containers.md)** | [Sequential Init Container Dependencies](lab-3-init-containers.md) | Blocking container startup until external service checks succeed | `03-init-container.yaml` | 15 mins |
| **[Lab 4](lab-4-sidecar-patterns.md)** | [Modern Native Sidecars (K8s 1.28+)](lab-4-sidecar-patterns.md) | Using `restartPolicy: Always` in init containers for sidecar proxies | `04-sidecar-pattern.yaml` | 15 mins |
| **[Lab 5](lab-5-probes.md)** | [Tuning Health Probes & Failure Scenarios](lab-5-probes.md) | Configuring Startup, Liveness, and Readiness probes; simulating app failures | `05-probe-tuning.yaml` | 20 mins |
| **[Lab 6](lab-6-debugging-playbook.md)** | [Debugging CrashLoopBackOff & OOMKilled](lab-6-debugging-playbook.md) | Real-world diagnostic walkthrough of failing applications | `06-broken-pod.yaml` | 20 mins |

---

## 🛠️ Prerequisites & Setup

To execute these labs successfully, ensure you have:
1. A local Kubernetes dev cluster. **Kind** (Kubernetes in Docker) or **Minikube** is highly recommended.
   * *Kind setup:* `kind create cluster --name day-4`
2. The `kubectl` CLI installed and connected to your cluster context.
3. Access to a command terminal (bash, zsh, or powershell).
