# 📚 Advanced Resources & Reference Material
## 30 Days of Production Kubernetes — Day 4

Expand your knowledge of Pod internals, container runtimes, and Linux namespace plumbing with this curated list of elite resources.

---

## 📄 Official Specifications & KEPs

* **[KEP-753: Sidecar Containers](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/753-sidecar-containers):** Read the design document that introduced native sidecars (containers with `restartPolicy: Always` in `initContainers`) in Kubernetes 1.28.
* **[OCI Image Format Specification](https://github.com/opencontainers/image-spec):** Understand how container layers, entrypoints, and commands are defined at the Open Container Initiative level.
* **[CNI (Container Network Interface) Specification](https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md):** The official standard detailing how runtime environments interact with network plugins to allocate IP addresses and setup namespaces.

---

## 🗃️ Under the Hood: Kubernetes Source Code

If you want to understand how Pods are built, look at the code written by the Kubernetes authors:

* **[Kubelet SyncPod Loop (`kuberuntime_manager.go`)](https://github.com/kubernetes/kubernetes/blob/master/pkg/kubelet/kuberuntime/kuberuntime_manager.go):** The core code where Kubelet calculates the changes between actual state and desired state of a Pod, running steps like:
  * Creating the Sandbox container (Pause container).
  * Launching Init containers sequentially.
  * Launching standard and native sidecar containers.
* **[Pause Container Source Code (`pause.c`)](https://github.com/kubernetes/kubernetes/blob/master/build/pause/pause.c):** The source code of the infrastructure pause container. It is written in C and is only 80 lines long. It catches system interrupts and calls `pause()` to keep namespaces alive.

---

## 📖 Deep Dives & Articles

* **[namespaces(7) - Linux Manual Page](https://man7.org/linux/man-pages/man7/namespaces.7.html):** The foundational Linux kernel manual page detailing all namespace types (`CLONE_NEWNET`, `CLONE_NEWPID`, `CLONE_NEWIPC`, etc.).
* **[Container Networking From Scratch](https://lagunita.stanford.edu/):** Detailed tutorials on how to manually create network namespaces, virtual ethernet pairs, and route traffic using Linux tools (`ip netns`, `brctl`, `iptables`).
* **[Debugging Pods with Ephemeral Containers](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/):** Step-by-step documentation on using the `kubectl debug` command to join running namespaces without breaking the pod lifecycle.
