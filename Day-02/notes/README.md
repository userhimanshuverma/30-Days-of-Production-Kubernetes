# 📖 Day 02 Notes: Container Internals & Isolation Primitives

## Introduction: Deconstructing the "Container"

To a systems engineer, **there is no such thing as a "container."** 

If you log into a Linux worker node and search the kernel for a structure or data type named `struct container`, you will find absolutely nothing. The kernel has no native concept of a container. 

Instead, a "container" is simply a **normal Linux process** that is constrained and isolated using native kernel features:
1.  **Namespaces:** Restrict what the process can **see**.
2.  **Control Groups (cgroups):** Restrict what the process can **use**.
3.  **Storage Drivers (OverlayFS/Union mounts):** Provide a distinct **filesystem view**.
4.  **Security Profiles (AppArmor/Seccomp):** Restrict what system operations the process can **do**.

In this document, we will demystify how these kernel structures work together to create the container abstraction.

---

## 1. Linux Namespaces: Isolating What Processes See

Namespaces partition kernel resources. They ensure that a set of processes sees resources differently than another set of processes. There are currently seven primary namespaces used by modern container runtimes:

| Namespace Type | Flag (Syscall) | What It Isolates | Why It Matters to Kubernetes |
| :--- | :--- | :--- | :--- |
| **PID** (Process ID) | `CLONE_NEWPID` | Process IDs, trees, and signals | Prevents containers from seeing or killing host/other pod processes. Inside the container, the main application starts as **PID 1** (acting as init). |
| **NET** (Network) | `CLONE_NEWNET` | Network devices, IP routing tables, port bindings, firewall rules | Provides each pod with its own IP address, local interface (`lo`), and independent port bindings. |
| **MNT** (Mount) | `CLONE_NEWNS` | File system mount points | Allows containers to have their own isolated root filesystem (`/`) without affecting the host's disks. |
| **UTS** (Hostnames) | `CLONE_NEWUTS` | Hostname and NIS domain name | Allows each pod to define its own hostname (e.g., matching the pod name) independently of the host. |
| **IPC** (Inter-Process) | `CLONE_NEWIPC` | System V IPC, POSIX message queues, shared memory | Prevents processes in different containers from communicating via shared memory segments (`shm`). |
| **USER** (Users/Groups) | `CLONE_NEWUSER` | User and group ID mappings | Maps a non-root user on the host (e.g., UID 10001) to the root user inside the container (UID 0). Essential for non-root execution. |
| **CGROUP** (cgroups) | `CLONE_NEWCGROUP` | The view of `/sys/fs/cgroup` | Conceals the overall host cgroup hierarchy, showing the container only its local resource node. |

---

### Low-Level Namespace Syscalls
How does a process end up in a namespace? The Linux kernel exposes three fundamental system calls:

#### A. `clone(..., int flags)`
Unlike `fork()`, which duplicates a process into the same namespaces, `clone()` spawns a new child process with flags specifying which new namespaces to allocate:
```c
// Example: Creating a process in a new network and PID namespace
int child_pid = clone(child_func, stack_ptr, CLONE_NEWPID | CLONE_NEWNET | SIGCHLD, NULL);
```

#### B. `unshare(int flags)`
Allows the calling process to detach *itself* from its current namespaces and allocate new ones on the fly without spawning a child. This is what the `unshare` command-line utility uses.

#### C. `setns(int fd, int nstype)`
Allows a process to join an *existing* namespace. The target namespace is represented by a file descriptor to a pseudo-file in `/proc/<PID>/ns/`.
*   *Production Use Case:* This is exactly how `kubectl exec` works. The container runtime calls `setns()` to attach a new shell process (like `/bin/sh`) to the namespace file descriptors of an already running container process.

---

## 2. Linux Control Groups (cgroups): Limiting What Processes Use

While namespaces prevent a process from *seeing* resources, they do not stop a process from consuming them. Without control groups, a single containerized process could consume 100% of host RAM and CPU, crashing the node. This is the **Noisy Neighbor** problem.

Control groups (cgroups) organize processes hierarchically and apply strict resource accounting and limits.

### cgroups v1 vs. cgroups v2
Historically, cgroups v1 was structured around separate trees per resource type (controller). This created synchronization bugs and high overhead. Modern systems use **cgroups v2**, which features a unified hierarchy where every process belongs to exactly one leaf node in a single tree.

| Feature | cgroups v1 (Legacy) | cgroups v2 (Modern / Production Standard) |
| :--- | :--- | :--- |
| **Hierarchy** | Multiple resource-specific trees. A process can belong to different nodes in different trees. | A single, unified process tree. Every controller (CPU, Memory, I/O) is applied to the same nodes. |
| **Path (sysfs)** | `/sys/fs/cgroup/<controller>/` | `/sys/fs/cgroup/` (Unified) |
| **OOM Behaviour** | The Out-Of-Memory Killer immediately kills the offending process. | Offers improved OOM handling and notification. Entire cgroup sub-tree can be terminated cleanly as a unit. |
| **Throttling Math** | Uses shares, period, and quota parameters (`cpu.shares`, `cpu.cfs_quota_us`). | Uses a cleaner `cpu.max` system defining max microseconds of usage per period. |

### How Container Runtimes Configure Limits (Under the Hood)
When you define resource limits in Kubernetes:
```yaml
resources:
  limits:
    cpu: "500m"      # 0.5 CPU cores
    memory: "256Mi"  # 256 Megabytes
```
The high-level runtime translates these limits and instructs `runc` to write values into the cgroup filesystem:
1.  **CPU Limit:** `500m` means "allow the container to use 50,000 microseconds of CPU time every 100,000 microseconds."
    *   `runc` writes `50000 100000` to `/sys/fs/cgroup/kubepods.slice/.../cpu.max`.
2.  **Memory Limit:** `256Mi` (268,435,456 bytes) is a hard memory boundary.
    *   `runc` writes `268435456` to `/sys/fs/cgroup/kubepods.slice/.../memory.max`.
    *   If the processes inside this cgroup allocate more than this number, the kernel triggers the **OOM Killer** and terminates the main process with **Exit Code 137**.

---

## 3. Container Runtimes & OCI Standards

To ensure interoperability, the industry established the **Open Container Initiative (OCI)**. OCI decouples container tools into three standards:
1.  **Image Specification:** Defines the layout and format of container image archives (layers, manifests, configurations).
2.  **Runtime Specification:** Defines how an unpacked container image on disk (an OCI Bundle) is executed by the kernel.
3.  **Distribution Specification:** Defines how container registries host, push, and pull images.

```
+-------------------------------------------------------------+
|                     Kubelet (Kubernetes Node Agent)         |
+-------------------------------------------------------------+
                               |
                               | (CRI API via gRPC)
                               v
+-------------------------------------------------------------+
|             High-Level Runtime (containerd / CRI-O)         |
+-------------------------------------------------------------+
                               |
                               | (Generates config.json & unpacked rootfs)
                               v
+-------------------------------------------------------------+
|             Low-Level Runtime (runc / crun)                |
+-------------------------------------------------------------+
                               |
                               | (Invokes Kernel Syscalls)
                               v
+-------------------------------------------------------------+
|                       Linux Kernel                          |
+-------------------------------------------------------------+
```

### High-Level vs. Low-Level Runtimes
Runtimes are split into two categories to separate management operations from raw kernel interactions:

#### High-Level Runtimes (CRI Runtimes)
*   **Examples:** `containerd`, `CRI-O`
*   **Role:** Manage the lifecycle of containers, images, and networking at a high level. They handle:
    *   Listening to the Kubelet over the **Container Runtime Interface (CRI)** gRPC API.
    *   Pulling images from registries, verifying signatures, and unpacking them on disk.
    *   Setting up network interfaces (using CNI plugins).
    *   Generating the standardized OCI `config.json` bundle specification.
    *   Spawning low-level runtimes to execute the process.

#### Low-Level Runtimes (OCI Executors)
*   **Examples:** `runc` (written in Go, standard), `crun` (written in C, very fast/low memory), `gVisor` (sandboxed kernel), `Kata Containers` (hypervisor isolated).
*   **Role:** Execute a container process given an unpacked directory (rootfs) and a `config.json` file.
    1.  Read `config.json`.
    2.  Set up namespaces (`clone`/`unshare`).
    3.  Set up cgroups (`/sys/fs/cgroup`).
    4.  Configure storage mount points.
    5.  Pivot the root directory (`pivot_root`).
    6.  Execute the target application process.
    *   *Note:* The low-level runtime exits immediately after launching the container process. The monitoring of the process is then handed over to a helper daemon called a **shim** (e.g. `containerd-shim`).

---

## 4. OverlayFS: Stacking Filesystem Layers

A container image is a tarball of layers. To run a container efficiently without copying gigabytes of files for every instance, Linux uses Union Filesystems—primarily **OverlayFS**.

OverlayFS takes two or more directories on a host and presents them as a single, merged directory.

### OverlayFS Core Directories
When OverlayFS mounts, it uses four directories:
1.  **`lowerdir`:** The read-only directories containing the base operating system and application files (the container image layers). Multiple lower directories can be stacked (e.g., `lowerdir=layer3:layer2:layer1`).
2.  **`upperdir`:** The writable directory. When a process inside the container writes, creates, or modifies a file, OverlayFS writes it here.
3.  **`merged`:** The unified view. This directory acts as the filesystem root (`/`) seen by the processes inside the container. It dynamically merges `upperdir` and `lowerdir`.
4.  **`workdir`:** A private directory used internally by the kernel for atomic transactions (like creating a file before shifting it to `upperdir`).

### The Copy-on-Write (CoW) Principle
*   **Read Operation:** If a process reads a file, OverlayFS looks for it in the `upperdir` first. If it's not there, it reads it from the `lowerdir`.
*   **Write/Modify Operation:** If a process attempts to edit a read-only file present in the `lowerdir`, OverlayFS executes a **Copy-on-Write**:
    1.  It duplicates the file from `lowerdir` to `upperdir`.
    2.  It applies the modifications to the copy in the `upperdir`.
    3.  Because `upperdir` has precedence, the container process sees the updated version in `merged`, while the underlying image layer in `lowerdir` remains completely untouched and safe to share with other containers.
*   **Delete Operation:** If a process deletes a file present in the `lowerdir`, OverlayFS cannot delete the file from the read-only layer. Instead, it creates a special device file in the `upperdir` called a **whiteout file** (or a character device with major/minor number `0/0`). This file acts as a mask, hiding the file from the `merged` directory view.
