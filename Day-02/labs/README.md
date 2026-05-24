# 🛠️ Day 02 Labs: Container Internals Hands-On Index

Welcome to the hands-on practice labs for Day 02. In these labs, we will strip away Docker command wrappers and interact directly with the Linux kernel APIs to inspect, control, and manipulate containerized environments.

---

## 💻 Prerequisites & Setup

To run these labs successfully, you need:
1.  **A Linux environment** (Ubuntu 20.04/22.04 LTS is highly recommended).
    *   If you are on Windows, use a local VM (via VirtualBox or Hyper-V) or **WSL2 (Windows Subsystem for Linux)**.
    *   If you are on macOS, run a Linux VM using Multipass, Lima, or UTM.
2.  **Sudo/Root Privileges:** Many namespaces and cgroups commands require root access.
3.  **Installed Tools:**
    *   `docker` or `containerd`
    *   `cgroup-tools` (for cgroups manual management)
    *   `stress` or `stress-ng`
    *   `jq`

---

## 🗺️ Lab Roadmap

Each lab is structured to guide you step-by-step from zero to deep architectural understanding:

| Lab Guide | Level | Focus | Primary Commands/Paths |
| :--- | :--- | :--- | :--- |
| **[Lab 1: Inspecting Namespaces](lab-1-namespaces.md)** | Beginner | View running container namespace IDs. | `lsns`, `readlink /proc/<PID>/ns/*`, `nsenter` |
| **[Lab 2: Manual cgroups Exploration](lab-2-cgroups.md)** | Medium | Navigate the cgroups filesystem. | `/sys/fs/cgroup/`, `cgcreate`, `cgclassify` |
| **[Lab 3: Spawn Isolated Processes](lab-3-isolated-process.md)** | Medium | Create namespaces manually from CLI. | `unshare`, `pivot_root`, `chroot` |
| **[Lab 4: Runtime Architecture Deep Dive](lab-4-runtime-architecture.md)** | Medium | Interact directly with `containerd` and `runc`. | `ctr`, `runc list`, `containerd-shim` |
| **[Lab 5: Mount OverlayFS Manually](lab-5-filesystem-layers.md)** | Advanced | Mount, modify, and delete OverlayFS layers. | `mount -t overlay ...`, `lowerdir`, `upperdir` |
| **[Lab 6: VM vs. Container Benchmarks](lab-6-vm-vs-container.md)** | Medium | Compare boot speed and resource overhead. | `time`, `ps`, memory footprints |
| **[Lab 7: Simulating Resource Exhaustion](lab-7-resource-exhaustion.md)** | Advanced | Induce memory OOM kills and CFS throttling. | `stress`, `/sys/fs/cgroup/cpu.stat` |
