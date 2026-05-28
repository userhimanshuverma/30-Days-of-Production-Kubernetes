# 🛠️ Lab 5: Inspecting kube-proxy & iptables Rules

In this lab, you will dive into the worker node's operating system to inspect the raw network rules created by `kube-proxy` that control service routing.

---

## Step 1: Access the Node Operating System
We will inspect a worker node. If you are using **Kind**, each node is a Docker container. We can execute commands directly on the node using `docker exec`.

List your docker containers:
```bash
docker ps | grep worker
```

**Expected Output**:
```text
c6b7593da1a2   kindest/node:v1.27.3   "/usr/local/bin/entr…"   24 hours ago   kind-worker
```

---

## Step 2: Dump the NAT Table Rules
We will run `iptables-save` inside the worker node to see all active NAT routing rules. Let's redirect the output to a file so we can inspect it:

```bash
# Execute on the kind node host
docker exec kind-worker iptables-save -t nat > node-iptables.txt
```

*(If you are running on minikube, run `minikube ssh` and execute `sudo iptables-save -t nat > /tmp/node-iptables.txt`)*

---

## Step 3: Search for Service Chains
Open `node-iptables.txt` and search for our backend service: `web-backend-service`. Alternatively, run a grep command:

```bash
grep "web-backend-service" node-iptables.txt
```

**Expected Output**:
```text
-A KUBE-SERVICES -d 10.96.14.22/32 -p tcp -m comment --comment "default/web-backend-service:http" -j KUBE-SVC-K2G6P76OJUHTNXWS
```

This tells us:
* Any packet destined for `10.96.14.22/32` (the ClusterIP) on port 80/TCP should jump (`-j`) to a custom chain named `KUBE-SVC-K2G6P76OJUHTNXWS`.

---

## Step 4: Trace the Service Chain rules
Now let's grep for that specific chain name to see how it load-balances traffic:

```bash
grep "KUBE-SVC-K2G6P76OJUHTNXWS" node-iptables.txt
```

**Expected Output**:
```text
:KUBE-SVC-K2G6P76OJUHTNXWS - [0:0]
-A KUBE-SVC-K2G6P76OJUHTNXWS -m comment --comment "default/web-backend-service:http" -m statistic --mode random --probability 0.33333333349 -j KUBE-SEP-3F6G7D3E2F1B4A5C
-A KUBE-SVC-K2G6P76OJUHTNXWS -m comment --comment "default/web-backend-service:http" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-9R8Q7P6O5N4M3L2K
-A KUBE-SVC-K2G6P76OJUHTNXWS -m comment --comment "default/web-backend-service:http" -j KUBE-SEP-8Z7Y6X5W4V3U2T1S
```

Notice the **statistic random probability** rules:
1. First rule intercepts the packet and routes to endpoint `KUBE-SEP-3F6G7D3E2F1B4A5C` with a `0.33` (33%) probability.
2. If not matched, the packet goes to the second rule, which routes to endpoint `KUBE-SEP-9R8Q7P6O5N4M3L2K` with a `0.50` (50%) probability.
3. If not matched, it defaults to the final rule `KUBE-SEP-8Z7Y6X5W4V3U2T1S` (which receives the remaining 33% of overall traffic).

---

## Step 5: Trace the Endpoint Chain (DNAT)
Let's see what happens inside one of the endpoint chains (e.g., `KUBE-SEP-3F6G7D3E2F1B4A5C`):

```bash
grep "KUBE-SEP-3F6G7D3E2F1B4A5C" node-iptables.txt
```

**Expected Output**:
```text
:KUBE-SEP-3F6G7D3E2F1B4A5C - [0:0]
-A KUBE-SEP-3F6G7D3E2F1B4A5C -p tcp -m comment --comment "default/web-backend-service:http" -j DNAT --to-destination 10.244.1.5:8080
```

This is where the magic happens:
* The rule performs **DNAT (Destination NAT)**, rewriting the destination IP of the packet from the ClusterIP (`10.96.14.22`) to the target Pod IP (`10.244.1.5:8080`).
* Once DNAT is applied, the packet is standard IP traffic routed by the Linux kernel directly to the pod.
