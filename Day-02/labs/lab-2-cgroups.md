# Lab 2: Exploring cgroups Manually

In this lab, you will manually interact with the cgroups pseudo-filesystem to enforce resource constraints on local shell processes.

---

## Step 1: Detect cgroups Version
Linux distributions run either cgroups v1 or unified cgroups v2. Verify which version your host runs:
```bash
mount | grep cgroup
```
*   **cgroups v2 (Unified):** You will see a line like:
    `cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime,nsdelegate)`
*   **cgroups v1 (Legacy):** You will see multiple entries mounting separate controllers (e.g. `/sys/fs/cgroup/memory`, `/sys/fs/cgroup/cpu`).

---

## Step 2: Set Up memory Limits on cgroups v2 (Modern Standard)
If your host runs **cgroups v2**:

1.  **Create a target group:**
    Create a new sub-folder inside `/sys/fs/cgroup/`. The kernel will automatically populate it with configuration files:
    ```bash
    sudo mkdir -p /sys/fs/cgroup/demo-limit
    ls -l /sys/fs/cgroup/demo-limit
    ```
2.  **Define a Memory Limit:**
    Set the maximum memory to **32MB** by writing `33554432` bytes to the `memory.max` control file:
    ```bash
    sudo sh -c 'echo "33554432" > /sys/fs/cgroup/demo-limit/memory.max'
    # Confirm the limit was written
    cat /sys/fs/cgroup/demo-limit/memory.max
    ```
3.  **Ensure Swap is Disabled/Limited:**
    To ensure our test process does not swap memory to disk instead of crashing, set swap limits to zero:
    ```bash
    sudo sh -c 'echo "0" > /sys/fs/cgroup/demo-limit/memory.swap.max'
    ```

---

## Step 3: Set Up memory Limits on cgroups v1 (Legacy)
If your host runs **cgroups v1**:

1.  **Create a target group:**
    ```bash
    sudo mkdir -p /sys/fs/cgroup/memory/demo-limit
    ```
2.  **Define a Memory Limit:**
    Write the 32MB limit to the memory limit file:
    ```bash
    sudo sh -c 'echo "33554432" > /sys/fs/cgroup/memory/demo-limit/memory.limit_in_bytes'
    # Disable swap access
    sudo sh -c 'echo "0" > /sys/fs/cgroup/memory/demo-limit/memory.memsw.limit_in_bytes'
    ```

---

## Step 4: Attach a Process to the cgroup
Open a new terminal shell or use the current shell. We will restrict the shell process by writing its Process ID (PID) to the cgroup's task/procs controller.

1.  **Check current shell PID:**
    ```bash
    echo $$
    # Example output: 4321
    ```
2.  **Write the shell PID to the cgroup procs list:**
    *   **On cgroups v2:**
        ```bash
        sudo sh -c "echo $$ > /sys/fs/cgroup/demo-limit/cgroup.procs"
        ```
    *   **On cgroups v1:**
        ```bash
        sudo sh -c "echo $$ > /sys/fs/cgroup/memory/demo-limit/tasks"
        ```
    Every command and child process spawned by this shell is now constrained by the 32MB limit.

---

## Step 5: Test and Trigger the OOM Killer
Let's verify the constraint works. Run a tool or a short script to allocate more than 32MB of RAM. We will use `stress`:
```bash
# Attempt to allocate 50MB of RAM
stress --vm 1 --vm-bytes 50M --timeout 10s
```
*Expected Output:*
```text
stress: info: [4410] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
stress: FAIL: [4410] (415) <-- worker 4411 reaped by signal 9 (SIGKILL)
stress: FAIL: [4410] (391) active daemon failed
```
Notice that the process was terminated immediately by **Signal 9 (SIGKILL)**.
Check kernel logs on the host:
```bash
dmesg -T | grep -i "demo-limit"
```
You will find log entries showing the kernel invoked the OOM killer on the `stress` process due to exceeding the memory limit in the cgroup.

---

## Clean Up
Remove the cgroup directory. On cgroups v2, you must ensure all processes have exited the cgroup before you can delete it:
```bash
# Re-attach shell to root cgroup (cgroups v2)
sudo sh -c "echo $$ > /sys/fs/cgroup/cgroup.procs"
# Delete the folder
sudo rmdir /sys/fs/cgroup/demo-limit
```
*(If on cgroups v1, run `sudo rmdir /sys/fs/cgroup/memory/demo-limit`)*
