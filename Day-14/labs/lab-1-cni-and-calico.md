# Lab 1: CNI and Calico Network Plumbing

This lab guides you through inspecting how a CNI plugin sets up networks, traces network namespaces, identifies `veth` interfaces on worker nodes, and analyzes routing tables.

---

## Prerequisites
* A local multi-node Kubernetes cluster (e.g. created with `kind` or `minikube` using a CNI-capable configuration).
* The `kubectl` command-line utility installed.
* Access to run commands on the cluster's worker nodes (e.g. via `docker exec` for Kind or `minikube ssh` for Minikube).

---

## Step 1: Install Calico CNI (If not already installed)

If you are running a cluster without a CNI plugin, or configured Kind to run without its default CNI, install Calico using the official operator manifests:

```bash
# 1. Install the Tigera Calico Operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

# 2. Deploy custom resources to trigger Calico CNI creation
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml
```

Monitor the deployment until all pods in the `calico-system` namespace are running:
```bash
kubectl get pods -n calico-system -w
```

---

## Step 2: Explore CNI Configuration Directories

The CNI specification dictates that network configurations reside in `/etc/cni/net.d/` and binaries reside in `/opt/cni/bin/`. Let's inspect these.

Access your worker node. If using Kind (with node name `kind-control-plane`):
```bash
docker exec -it kind-control-plane bash
```

Once inside the host terminal, check the CNI configurations:
```bash
ls -l /etc/cni/net.d/
```

**Expected Output:**
```
total 4
-rw-r--r-- 1 root root 647 Jun  5 14:15 10-calico.conflist
```

Read the file contents:
```bash
cat /etc/cni/net.d/10-calico.conflist
```

**Key parts to notice in the JSON payload:**
* `"type": "calico"`: Directs containerd to run `/opt/cni/bin/calico`.
* `"ipam"` block: Defines which IP address management plugin is invoked (`"type": "calico-ipam"`).
* `"mtu"` config: Configures virtual interface sizes.

Verify that the CNI binaries exist:
```bash
ls -l /opt/cni/bin/
```
You should see executable binaries for `calico`, `calico-ipam`, `loopback`, `host-local`, `portmap`, etc.

---

## Step 3: Trace a Pod's Virtual Network Interface (veth)

Let's trace exactly how a Pod's container adapter (`eth0`) maps to the host's virtual adapter (`veth`).

1. Deploy a sample debug pod:
```bash
kubectl run network-debug-pod --image=nginx --restart=Never
```

2. Wait for it to schedule and get an IP:
```bash
kubectl get pod network-debug-pod -o wide
```
*Note down the Pod IP (e.g. `10.244.186.201`) and the Node it is running on (e.g. `kind-worker`).*

3. Find the container ID and process ID (PID) on the worker node. Access the node via shell:
```bash
docker exec -it kind-worker bash
```

4. Retrieve the container's virtual interface index from inside the container:
```bash
# Locate container runtime namespaces using 'crictl' or inspect sysfs
# Let's get the interface index directly by running inside the container:
kubectl exec network-debug-pod -- ip link show eth0
```

**Expected Output:**
```
3: eth0@if14: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether f2:f4:ac:11:ba:a7 brd ff:ff:ff:ff:ff:ff link-netnsid 0
```
*Look at `eth0@if14`. The `if14` indicates that this interface is linked to interface index **14** in the host's root namespace.*

5. On the host node shell (`kind-worker`), locate interface index `14`:
```bash
ip link | grep -A 1 "^14:"
```

**Expected Output:**
```
14: cali83f9eba8ac0@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether ee:ee:ee:ee:ee:ee brd ff:ff:ff:ff:ff:ff link-netnsid 0
```
*Aha! The host-side virtual adapter is `cali83f9eba8ac0`. It links back to interface index `3` inside the container namespace.*

You have successfully traced the two ends of the Virtual Ethernet (`veth`) patch cord!

---

## Step 4: Inspect the Namespace and Host Routing Tables

1. Let's inspect the routing table inside the container namespace:
```bash
kubectl exec network-debug-pod -- ip route
```

**Expected Output:**
```
default via 169.254.1.1 dev eth0 
169.254.1.1 dev eth0 scope link
```
*Note: Calico uses a link-local dummy gateway `169.254.1.1`. Any packet leaving the container is sent out of `eth0` directly to the host.*

2. Inspect the host node routing table (`kind-worker`) to see how it directs packets to the Pod IP:
```bash
ip route | grep 10.244.186.201
```

**Expected Output:**
```
10.244.186.201 dev cali83f9eba8ac0 scope link
```
This tells the host kernel: "If a packet comes in for `10.244.186.201`, forward it directly to the virtual interface `cali83f9eba8ac0`, which leads straight into the container namespace."

---

## Clean Up
```bash
kubectl delete pod network-debug-pod
```
Observe that the host-side interface `cali83f9eba8ac0` is instantly destroyed, and the routing entry is removed.
