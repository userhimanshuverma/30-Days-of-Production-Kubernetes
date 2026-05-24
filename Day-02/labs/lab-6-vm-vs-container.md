# Lab 6: Benchmarking VM vs. Container Performance

In this lab, you will perform simple benchmarks to compare the startup speed and memory overhead of Virtual Machines vs. Containers.

---

## 1. Startup Speed Benchmark
A container is simply a process started with modified namespace attributes. Spawning a process is a native kernel operation that takes milliseconds. A Virtual Machine must boot an entire Guest Operating System (BIOS, bootloader, kernel initialization, systemd init), taking seconds or minutes.

### Container Startup Time Test
Let's measure how long it takes to start an Alpine container and execute a single command:
```bash
# time measures real (wall clock), user CPU, and system CPU time
time docker run --rm alpine echo "Hello World"
```
*Expected Output:*
```text
Hello World

real    0m0.245s
user    0m0.015s
sys     0m0.012s
```
Spawning the container and executing the command took **less than 250 milliseconds**. If the image is already cached, it takes even less time.

### Virtual Machine Boot Time Test
If you have access to a local VM (e.g., via Multipass or Virsh), measure the boot time of a mini-VM:
```bash
# If using multipass
time multipass start micro-vm
```
If you do not have a command-line VM builder, run a check on any VM you can boot. The standard boot cycle takes anywhere from **8 to 25 seconds**, representing a **30x to 100x slower** initialization time compared to containers.
*   **Production Impact:** In Kubernetes, this startup speed difference is what enables rapid horizontal autoscaling (HPA) to handle traffic spikes. Spawning 50 new pods takes under a second, whereas booting 50 VMs would take minutes.

---

## 2. Memory Overhead Benchmark
A Virtual Machine reserves a block of RAM for its Guest OS Kernel, systemd services, and drivers, regardless of whether your app is active. A container process only consumes what its application code allocates.

### Analyze Guest OS Memory Footprint
Log into a clean Linux Virtual Machine (or check WSL2 shell) and query the memory usage *before* running any user applications:
```bash
free -h
```
*Expected Output:*
```text
              total        used        free      shared  buff/cache   available
Mem:          7.7Gi       480Mi       6.8Gi        12Mi       450Mi       7.0Gi
```
The base operating system consumes **~480MB of RAM** just to idle. If you run 10 VMs on a host node to isolate 10 simple APIs, you waste **~4.8GB of RAM** purely on running Guest Kernels!

### Analyze Container Memory Footprint
Now check the memory overhead of running an idle container on your host. Start a container:
```bash
docker run -d --name idle-alpine alpine sleep 3600
```
Inspect the actual memory consumption of this container process on the host:
```bash
# Find host PID
IDLE_PID=$(docker inspect --format '{{.State.Pid}}' idle-alpine)
# Read RSS (Resident Set Size) memory from procfs
cat /proc/$IDLE_PID/status | grep -i rss
```
*Expected Output:*
```text
VmRSS:        428 kB
```
The container process consumes only **428 Kilobytes of RAM** (less than 0.5MB). Because it shares the host kernel, it does not allocate any redundant OS services. This allows for massive density in production systems: you can pack thousands of isolated containers on a single physical host node.

---

## Clean Up
```bash
docker rm -f idle-alpine
```
