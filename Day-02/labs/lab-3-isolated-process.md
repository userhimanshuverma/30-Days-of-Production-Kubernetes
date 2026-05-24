# Lab 3: Spawning Isolated Processes (Building a Container from Scratch)

In this lab, you will combine namespace isolation and a custom root directory (`chroot`) to spawn a fully isolated process that mimics a running container, without using any container runtime engine.

---

## Step 1: Prepare the Container Root Directory
To run a container, we need a root filesystem (`rootfs`). We will download a minimal Alpine Linux root directory and unpack it.

```bash
# Create directory structure
mkdir -p /tmp/my-container/rootfs
cd /tmp/my-container

# Download Alpine minimal rootfs
curl -sSL -o alpine.tar.gz https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-minirootfs-3.18.4-x86_64.tar.gz

# Extract the archive into the rootfs directory
tar -xzf alpine.tar.gz -C rootfs/
rm alpine.tar.gz
```
Inspect the directory. You will see standard Linux folders (`/bin`, `/etc`, `/lib`, `/usr`) that make up the image layer of an Alpine container:
```bash
ls -la rootfs/
```

---

## Step 2: Spawn Isolated Namespaces using `unshare`
We will use the `unshare` command to run a shell process. We will pass flags to allocate new namespaces:
*   `-p`: New PID namespace.
*   `-f`: Fork a new child process to run the shell (required for PID namespace isolation to take effect).
*   `-m`: New Mount namespace.
*   `-u`: New UTS namespace (hostname).
*   `-n`: New Network namespace.

Run this command as root on the host:
```bash
sudo unshare -p -f -m -u -n chroot rootfs/ /bin/sh
```
*You are now inside the isolated root shell! Notice that the prompt changed to `/ #`.*

---

## Step 3: Configure UTS Namespace (Hostname)
From inside your new container shell, run:
```bash
hostname
# Output will be the host node's hostname. Let's change it:
hostname my-custom-container
hostname
# Output: my-custom-container
```
Open a separate terminal window on your host and run `hostname`. Note that the host's hostname remains completely unchanged. The UTS namespace isolates the changes.

---

## Step 4: Mount `/proc` and Inspect Processes
From inside your container shell, run `ps aux`:
```bash
ps aux
```
*Expected Output:*
```text
ps: can't open '/proc': No such file or directory
```
To view running processes, the `ps` command queries the `/proc` filesystem. Since we are in a new mount namespace, we must mount the pseudo `/proc` filesystem inside our local container space first:
```bash
# Mount virtual procfs inside container mount namespace
mount -t proc proc /proc
# Now query processes again
ps aux
```
*Expected Output:*
```text
PID   USER     TIME  COMMAND
    1 root      0:00 /bin/sh
    5 root      0:00 ps aux
```
You have successfully isolated the processes! The container shell has no visibility of other applications running on the host. It sees its primary shell as **PID 1**.

---

## Step 5: Verify Network Isolation
From inside the container shell, verify network adapters:
```bash
ip link show
```
*Expected Output:*
```text
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
```
Notice that the container has no network access (`eth0` is missing, only `lo` is present and it is shut down). It has no internet connectivity.

---

## Step 6: Exiting and Cleaning Up
To exit the container:
```bash
exit
```
Once you exit the shell, the container processes terminate. Because namespaces are tied to running processes, the namespaces disappear automatically.
Clean up the filesystem directories:
```bash
sudo rm -rf /tmp/my-container
```
