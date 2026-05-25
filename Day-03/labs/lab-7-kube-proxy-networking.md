# Lab 7: Debugging kube-proxy Networking

`kube-proxy` manages Service networking on cluster nodes by setting up Linux packet filter chains (iptables or IPVS). In this lab, you will audit the raw iptables rules written by kube-proxy, tracing a virtual ClusterIP service to its actual backing Pod IPs.

---

## 🏃 Step 1: Deploy a Service and Backing Pods
Let's deploy a service that targets two pods.

Write the following manifest to `manifests/01-nginx-deployment.yaml` (if not already there, overwrite or use this deployment):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: proxy-demo
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: proxy-demo
  template:
    metadata:
      labels:
        app: proxy-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
```

Now, create a ClusterIP Service to expose these pods:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: proxy-demo-svc
  namespace: default
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: proxy-demo
```
*(Save this service manifest as `manifests/05-proxy-service.yaml` and apply both)*:
```bash
# We will create the service yaml directly or apply:
kubectl apply -f manifests/01-nginx-deployment.yaml
kubectl apply -f manifests/05-proxy-service.yaml
```

Wait for the pods to run, then retrieve the Service ClusterIP and the IPs of the backing pods:
```bash
# Get Service IP
kubectl get svc proxy-demo-svc

# Get backing Pod IPs
kubectl get pods -l app=proxy-demo -o wide
```

*Assume:*
* Service ClusterIP: `10.96.128.44`
* Pod 1 IP: `10.244.1.4`
* Pod 2 IP: `10.244.2.3`

---

## 🏃 Step 2: Trace IPTables Chains inside the Worker Node
Exec into your worker node container:
```bash
docker exec -it k8s-internals-worker bash
```

In IPTables mode, `kube-proxy` inserts chains into the **NAT** table.
List all chains in the NAT table containing our Service name:
```bash
iptables -t nat -S | grep proxy-demo-svc
```

**Expected Output:**
```
-A KUBE-SERVICES -d 10.96.128.44/32 -p tcp -m comment --comment "default/proxy-demo-svc: cluster IP" -m tcp --dport 80 -j KUBE-SVC-F5W2J5UXO27QZ4Q7
```

### Analysis of the entrypoint:
Any packet entering the node destined for `10.96.128.44:80` is jumped (`-j`) to a custom service chain: `KUBE-SVC-F5W2J5UXO27QZ4Q7`.

Now, let's inspect the rules inside that specific Service chain:
```bash
iptables -t nat -S KUBE-SVC-F5W2J5UXO27QZ4Q7
```

**Expected Output:**
```
-N KUBE-SVC-F5W2J5UXO27QZ4Q7
-A KUBE-SVC-F5W2J5UXO27QZ4Q7 -m comment --comment "default/proxy-demo-svc:" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-X53NWRLUP6N2332N
-A KUBE-SVC-F5W2J5UXO27QZ4Q7 -m comment --comment "default/proxy-demo-svc:" -j KUBE-SEP-O6AXYYF4J6L7392M
```

### Analysis of Load Balancing:
Look at the `-m statistic --mode random --probability 0.50000000000` rule.
* **Random Probability Routing:** IPTables evaluates rules sequentially. To load-balance across 2 pods, it selects the first endpoint (`KUBE-SEP-X53NWRLUP6N2332N`) with a **50% (0.5)** probability.
* If the random choice fails, the packet falls through to the next rule, which jumps to the second endpoint (`KUBE-SEP-O6AXYYF4J6L7392M`) with a 100% probability.
* *If you had 3 pods, the probabilities would be 0.33 for the first pod, 0.50 for the remaining half of the traffic on the second, and 1.00 for the final fallthrough.*

---

## 🏃 Step 3: Inspect the Endpoint Chain (DNAT Translation)
Now let's inspect one of these endpoint (`SEP`) chains to see how the packet's destination IP is rewritten.
```bash
iptables -t nat -S KUBE-SEP-X53NWRLUP6N2332N
```

**Expected Output:**
```
-N KUBE-SEP-X53NWRLUP6N2332N
-A KUBE-SEP-X53NWRLUP6N2332N -p tcp -m comment --comment "default/proxy-demo-svc:" -m tcp -j DNAT --to-destination 10.244.1.4:80
```

### Analysis:
The rule applies **Destination NAT (`-j DNAT`)**, rewriting the packet's target address from the virtual ClusterIP (`10.96.128.44:80`) to the actual, physical Pod IP (`10.244.1.4:80`). The Linux kernel then routes the packet onto the virtual bridge or network tunnel.

Exit the worker node container:
```bash
exit
```

Clean up the deployments:
```bash
kubectl delete deployment proxy-demo
kubectl delete service proxy-demo-svc
```
---

## ⚡ Scale Implications: The IPTables Bottleneck
As you can see, routing a service requires traversing multiple custom chains and rule lookups.
* In a cluster with **10,000 services**, the NAT table will contain tens of thousands of rules.
* Because iptables rules are evaluated sequentially, packet routing latency increases linearly with the number of services.
* **Production Fix:** Switch `kube-proxy` to **IPVS mode**, which stores these mappings in constant-time $O(1)$ hash tables in kernel space, or deploy an eBPF-based CNI (like Cilium) to bypass the IPTables netfilter chains entirely.
