# Lab 4: Exploring Container Runtime Architecture (containerd and runc)

In this lab, you will bypass high-level developer engines like Docker and interact directly with **containerd** and **runc** to understand how Kubernetes orchestrates containers at a low level.

---

## Step 1: Query containerd namespaces via `ctr`
`containerd` utilizes namespaces (different from kernel namespaces) to isolate resources for different clients (e.g. Docker, Kubernetes, ctr CLI).

Use the `ctr` CLI (packaged directly with containerd) to list available containerd namespaces:
```bash
sudo ctr namespaces list
```
*Expected Output:*
```text
NAME    LABELS
default 
moby             # Namespace where Docker runs containers
k8s.io           # Namespace where Kubernetes (Kubelet) runs containers
```
*Note: If you run this inside a production Kubernetes cluster, you will see all your pods running inside the `k8s.io` namespace.*

---

## Step 2: Pull and Unpack an Image using `ctr`
Let's pull and unpack an image directly using `ctr`:
```bash
sudo ctr images pull docker.io/library/alpine:latest
# Verify the image is pulled
sudo ctr images list
```

---

## Step 3: Run a Container directly under `containerd`
Launch a container process named `ctr-demo`:
```bash
sudo ctr run -d docker.io/library/alpine:latest ctr-demo sleep 3600
# List running containerd tasks
sudo ctr tasks list
```
*Expected Output:*
```text
TASK        PID     STATUS
ctr-demo    8524    RUNNING
```

---

## Step 4: Inspect the containerd-shim on the Host
When `containerd` spawns a container, it creates a new **containerd-shim** process, which in turn calls `runc` to create the container. Once `runc` finishes creating and starting the container, it exits, leaving the `containerd-shim` to monitor the container.

Let's check the process tree on the host:
```bash
ps -ef | grep containerd-shim
```
*Expected Output:*
```text
root      8500   720  0 15:25 ?        00:00:00 containerd-shim -namespace default -id ctr-demo -address /run/containerd/containerd.sock
```
Notice that the parent process of the shim is `containerd` (PID 720), but the parent of the container process (`sleep 3600`) is the shim process itself.
*   **Why does this matter?** If `containerd` crashes or restarts, the shim processes keep running, preventing container processes from terminating. This ensures high availability.

---

## Step 5: Locate the OCI Bundle on disk
Before running a container, `containerd` unpacks the image filesystem and generates the OCI-compliant configuration file `config.json`. Let's inspect this OCI bundle:

```bash
# Navigate to the runtime state directory of the task
cd /run/containerd/io.containerd.runtime.v2.task/default/ctr-demo
ls -la
```
Inside this folder, you will find:
1.  `config.json`: The OCI Spec definition.
2.  `init.pid`: A file containing the active PID of the container process inside the host OS kernel.
3.  Standard streams: `rootfs` path, sockets, and configuration configurations.

Let's inspect the `config.json` configuration file:
```bash
cat config.json | jq .process.capabilities
```
You will see a list of default capabilities containerd assigns to the container process.

---

## Step 6: Query OCI processes via `runc`
Because `containerd-shim` uses standard OCI runtimes, we can query the containers using the low-level `runc` command directly:
```bash
sudo runc list
```
*Expected Output:*
```text
ID          PID         STATUS      BUNDLE                                                      CREATED                          OWNER
ctr-demo    8524        running     /run/containerd/io.containerd.runtime.v2.task/default/ctr-demo   2026-05-24T15:25:00.123456789Z   root
```
You can also run commands inside the container using runc:
```bash
sudo runc exec ctr-demo ps aux
```

---

## Clean Up
```bash
# Terminate the task inside containerd
sudo ctr tasks kill -s SIGKILL ctr-demo
# Delete the task representation
sudo ctr tasks delete ctr-demo
# Delete the container metadata
sudo ctr containers delete ctr-demo
```
Verify the shim process and OCI directory have been cleaned up automatically:
```bash
ps -ef | grep containerd-shim | grep ctr-demo
```
*(Should return empty).*
