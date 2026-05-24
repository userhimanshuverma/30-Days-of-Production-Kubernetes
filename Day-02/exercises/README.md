# 🏆 Day 02 Exercises: Building Containers & Configuring Resource Limits

Complete these challenges to test and apply your knowledge of container internals.

---

## 🎯 Challenge 1: The "Bash Container" Script

Your goal is to write a Shell script that uses Linux utilities (`unshare`, `cgcreate`, `pivot_root` or simple `chroot`) to spawn a shell that behaves like a basic container.

### Requirements
1.  **Isolation:** The shell must have its own isolated PID namespace, Mount namespace, and Network namespace.
2.  **Hostname:** The hostname inside the isolated shell must show as `production-day-02`.
3.  **Memory Limit:** The shell and its child processes must be restricted to a cgroup memory limit of **64MB**. If a child process tries to allocate more than 64MB inside the shell, the kernel should kill it (OOM).

### Template Script (`mock-container.sh`)
Create this file and complete the missing parts marked with `# TODO`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

# Define paths
ROOTFS_DIR="/tmp/container-root"
CGROUP_NAME="day02-container"

echo "=== [Step 1] Preparing root filesystem (chroot directory) ==="
mkdir -p "$ROOTFS_DIR"
# Copy minimal alpine structure or use busybox
if [ ! -d "$ROOTFS_DIR/bin" ]; then
  echo "Installing mini-alpine environment..."
  # Download and extract mini root filesystem
  curl -sSL https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-minirootfs-3.18.4-x86_64.tar.gz | tar -xz -C "$ROOTFS_DIR"
fi

echo "=== [Step 2] Configuring cgroups limit (64MB) ==="
# Determine if cgroups v1 or v2 is active
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  echo "Detected cgroups v2..."
  # Create a cgroup directory
  CG_PATH="/sys/fs/cgroup/$CGROUP_NAME"
  mkdir -p "$CG_PATH"
  # TODO: Write 64MB limit (67108864 bytes) to memory limit file
  echo "67108864" > "$CG_PATH/memory.max"
else
  echo "Detected cgroups v1..."
  CG_PATH="/sys/fs/cgroup/memory/$CGROUP_NAME"
  mkdir -p "$CG_PATH"
  # TODO: Write 64MB limit to memory limit file in cgroups v1
  echo "67108864" > "$CG_PATH/memory.limit_in_bytes"
fi

echo "=== [Step 3] Launching isolated container environment ==="
# TODO: Use unshare to create new PID, mount, UTS, and net namespaces,
# then chroot into $ROOTFS_DIR and set hostname to 'production-day-02'.
# Inside the container, mount /proc so 'ps' works correctly.
# Ensure that the shell process is attached to the cgroup we created.
# Hint: You can write the shell PID ($$) to cgroups.procs (v2) or tasks (v1)

# Write your execution commands below this line:
```

### Verification
Once complete, launch your script, open the isolated shell, and run:
```bash
# 1. Verify Hostname
hostname
# Expected: production-day-02

# 2. Verify PID namespace
ps aux
# Expected: You should only see PID 1 (your shell) and ps. No host processes!

# 3. Test memory cgroup limitation by running:
# (Inside container)
apk add --no-cache stress-ng
stress-ng --vm 1 --vm-bytes 80M --timeout 10s
# Expected: The process must be instantly OOMKilled by cgroup limit
```

---

## 🎯 Challenge 2: Multi-Tenant Hardening Manifest

Write a Kubernetes Pod manifest named `hardened-microservice.yaml` that meets the following corporate security requirements:

1.  **QoS Class:** Must be `Guaranteed` (both CPU and memory request/limit are exactly equal).
2.  **Resources:** CPU at `250m`, Memory at `128Mi`.
3.  **User Namespace:** Must run as user UID `20002` and group GID `20002`.
4.  **Filesystem Isolation:** Root filesystem must be mounted as **read-only** to prevent hackers from downloading scripts if they exploit it.
5.  **Syscall restriction:** Enforce standard `RuntimeDefault` seccomp profile.
6.  **Capabilities:** Drop `ALL` Linux kernel capabilities, but add back `NET_BIND_SERVICE` (if binding to ports < 1024 is required).

### Submission Verification
Run the manifest in a local Kind or Minikube cluster and verify it starts successfully. Verify the root filesystem is read-only by trying to write to `/tmp`:
```bash
kubectl exec -it hardened-microservice -- touch /tmp/testfile
# Expected: touch: /tmp/testfile: Read-only file system
```

---

## 📚 Verification Questions & Self-Assessment

1.  **What is the difference between `unshare` and `setns` system calls?**
    *   *Hint:* Which one allocates new namespaces for the current process, and which one joins an already existing namespace?
2.  **Why does running `top` or `free` inside a standard Docker container show the total memory and CPU of the host system instead of the container's cgroup limits?**
    *   *Hint:* How does `/proc/meminfo` interact with namespaces? How does the `LXCFS` utility solve this in production?
3.  **Explain what happens to a container's processes when its memory limit is exceeded vs. when its CPU limit is exceeded.**
4.  **In OverlayFS, if file `/app/config.json` exists in `lowerdir` and a process inside the container runs `echo 'new config' > /app/config.json`, which OverlayFS directory is modified, and does the original file in the image layer change?**
5.  **What role does `containerd-shim` play? Why doesn't `containerd` monitor container processes directly?**
    *   *Hint:* What happens to the containers if you restart the `containerd` systemd service?
