# Lab 1: Inspecting Linux Namespaces in Running Containers

In this lab, you will inspect how the Linux kernel maps namespaces to running container processes and use tools to attach directly to them.

---

## Step 1: Launch a Target Container
We need a running container to inspect. Start a simple background web server container:
```bash
docker run -d --name lab-web -p 8080:80 nginx:alpine
# Or if using containerd/nerdctl:
# nerdctl run -d --name lab-web -p 8080:80 nginx:alpine
```

## Step 2: Retrieve the Host Process ID (PID)
Containers run as normal host processes. Let's find the PID of the Nginx server on the host:
```bash
CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' lab-web)
echo "Container Host PID is: $CONTAINER_PID"
```

## Step 3: Read Namespace Symlinks via `/proc`
The Linux kernel exposes information about a process's namespaces inside the `/proc` filesystem under `/proc/<PID>/ns/`. Let's inspect them:
```bash
sudo ls -l /proc/$CONTAINER_PID/ns/
```
*Expected Output:*
```text
lrwxrwxrwx 1 root root 0 May 24 15:20 cgroup -> 'cgroup:[4026531835]'
lrwxrwxrwx 1 root root 0 May 24 15:20 ipc -> 'ipc:[4026532258]'
lrwxrwxrwx 1 root root 0 May 24 15:20 mnt -> 'mnt:[4026532256]'
lrwxrwxrwx 1 root root 0 May 24 15:20 net -> 'net:[4026532261]'
lrwxrwxrwx 1 root root 0 May 24 15:20 pid -> 'pid:[4026532259]'
lrwxrwxrwx 1 root root 0 May 24 15:20 user -> 'user:[4026531837]'
lrwxrwxrwx 1 root root 0 May 24 15:20 uts -> 'uts:[4026532257]'
```
### System Insight
Each line represents a namespace, and the number in brackets (e.g., `4026532261`) is the unique inode ID of that namespace. If two processes share the same net inode ID, they share the same network namespace and see the same interfaces/ports.

Compare the container's network namespace inode to your host's network namespace:
```bash
readlink /proc/self/ns/net
# Compare with:
readlink /proc/$CONTAINER_PID/ns/net
```
*Note: They will be completely different, confirming network isolation.*

## Step 4: Use `lsns` to List Namespaces
The `lsns` command reads files in `/proc` to list all active namespaces on the node:
```bash
sudo lsns -t net
```
Look for the line showing your container PID. It will list the number of processes in the namespace, the user who created it, and the command that triggered it (`nginx`).

## Step 5: Execute Commands inside the Namespace using `nsenter`
`kubectl exec` works under the hood using the `setns()` system call to run a shell process within the container's namespaces. We can perform this manually on the host using `nsenter`:
```bash
# Enter the mount and PID namespace of the container
sudo nsenter -t $CONTAINER_PID -m -p -- ps aux
```
*Expected Output:*
```text
PID   USER     TIME  COMMAND
    1 root      0:00 nginx: master process nginx -g daemon off;
   31 nginx     0:00 nginx: worker process
   32 root      0:00 ps aux
```
Notice that we did not run a container image. Instead, we executed the host's `/bin/ps` binary inside the container's namespace. The processes list is restricted to the container, and `nginx` appears as **PID 1**.
Try running `ip link show` inside the network namespace:
```bash
sudo nsenter -t $CONTAINER_PID -n ip link show
```
You will only see the loopback (`lo`) and the virtual interface (`eth0`), not the host's physical network adapters.

## Clean Up
```bash
docker rm -f lab-web
```
