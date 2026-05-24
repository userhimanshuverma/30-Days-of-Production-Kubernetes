# Lab 7: Simulating Container Resource Exhaustion in Production

In this lab, you will simulate resource exhaustion inside running containers to witness how the host kernel responds to memory starvation and CPU throttling.

---

## 1. Simulating Memory Exhaustion (OOMKilled)
We will run a container with a strict memory limit of **64MB** and trigger a memory allocation spike.

### Step 1: Run Memory Hog Container
Run a container with a `64m` memory limit:
```bash
docker run --name oom-test --memory=64m polinux/stress \
  stress --vm 1 --vm-bytes 128M --timeout 30s
```
*Expected Output:*
```text
stress: info: [1] dispatching hogs: 0 cpu, 0 io, 1 vm, 0 hdd
# (The command hangs for a split second, then returns to command prompt without success message)
```

### Step 2: Query Container Exit State
Let's inspect the container status:
```bash
docker inspect oom-test --format 'Status: {{.State.Status}} | OOMKilled: {{.State.OOMKilled}} | ExitCode: {{.State.ExitCode}}'
```
*Expected Output:*
```text
Status: exited | OOMKilled: true | ExitCode: 137
```
The exit code is **137**. In Linux/Unix, an exit code of `128 + N` indicates termination by a signal. Here, `137 = 128 + 9`, confirming the process was terminated by **Signal 9 (SIGKILL)** sent by the kernel OOM-killer.

---

## 2. Simulating CPU Throttling (CFS Bandwidth Control)
We will restrict a container to **0.2 CPU cores** and trigger a CPU-intensive loop to observe how the kernel throttles the process.

### Step 1: Run CPU Stress Container
Start a container with a strict limit of `0.2` CPUs (or `200m` milli-cores in Kubernetes terms):
```bash
docker run -d --name cpu-test --cpus=0.2 polinux/stress \
  stress --cpu 2 --timeout 600s
```

### Step 2: Retrieve the Container PID on Host
```bash
CPU_PID=$(docker inspect --format '{{.State.Pid}}' cpu-test)
```

### Step 3: Query cgroup CPU Stats
Wait 10-15 seconds for the stress processes to run, then check the cgroup metrics on the host node.

*   **If your host runs cgroups v2:**
    ```bash
    cat /sys/fs/cgroup/system.slice/docker-$(docker inspect --format '{{.Id}}' cpu-test).scope/cpu.stat
    # (If the docker slice path differs, check /sys/fs/cgroup/cpu.stat inside the container namespaces using nsenter)
    sudo nsenter -t $CPU_PID -m -C cat /sys/fs/cgroup/cpu.stat
    ```
*   **If your host runs cgroups v1:**
    ```bash
    cat /sys/fs/cgroup/cpu/docker/$(docker inspect --format '{{.Id}}' cpu-test)/cpu.stat
    ```

*Expected Output (cgroups v2):*
```text
usage_usec 15201294
user_usec 12102030
system_usec 3099264
nr_periods 1250          # Total elapsed scheduler periods
nr_throttled 980         # Number of times the processes were throttled
throttled_usec 42012093  # Cumulative time throttled (in microseconds)
```
Notice that `nr_throttled` is extremely high relative to `nr_periods`. Because the workload attempted to use 2 full cores while the container was restricted to 0.2, the kernel CFS scheduler repeatedly put the processes to sleep. The application did not crash, but its performance slowed down significantly.

---

## Clean Up
```bash
docker rm -f oom-test cpu-test
```
