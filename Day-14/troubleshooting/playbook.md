# 🚨 Day 14 Troubleshooting Playbook: Kubernetes Networking Internals

This playbook provides actionable diagnostic procedures and resolution scripts for the 10 most common networking failures encountered in production Kubernetes clusters.

---

## 1. Pod cannot reach Pod (Same Node vs. Cross-Node)

### Symptoms
* Application logs show connection timeouts (e.g. `Connection timed out` or `No route to host`).
* Testing connectivity between Pod A and Pod B fails.

### Diagnosis
Determine if the failure is local to the node or occurs only when crossing nodes:
```bash
# 1. Identify Pod IPs and Nodes
kubectl get pods -o custom-columns=NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName

# 2. Test local node routing: Exec into a pod on Node 1 and ping another pod on Node 1
kubectl exec <pod-a-node-1> -- ping -c 3 <pod-b-node-1-ip>

# 3. Test cross-node routing: Exec into a pod on Node 1 and ping a pod on Node 2
kubectl exec <pod-a-node-1> -- ping -c 3 <pod-c-node-2-ip>
```
* If **Same-Node fails:** The issue is likely host virtual plumbing (`veth` down, CNI crash, local iptables corruption).
* If **Cross-Node fails (but Same-Node works):** The issue is overlay network routing, BGP peering, or host firewall/cloud provider security groups blocking UDP 4789 (VXLAN) or Protocol 4 (IP-in-IP).

### Resolution
For Cross-Node failures, check if the overlay port is blocked on the hosts:
```bash
# Verify host UDP port 4789 is listening and open
nc -zuv -w5 <remote-node-ip> 4789
```
*If blocked, update cloud security groups to permit UDP port 4789 (VXLAN) or Protocol 4 (IP-in-IP).*

---

## 2. DNS works but TCP Traffic Fails

### Symptoms
* Resolving hostnames works (e.g. `nslookup backend` succeeds).
* Activating a connection (e.g. `curl http://backend`) hangs indefinitely.

### Diagnosis
This is a classic symptom of an **MTU size mismatch**.
Run a packet size test using ping with the `Don't Fragment` (DF) bit flag enabled to find the point where packets are dropped:
```bash
# Run ping inside the container with large packets and DF bit set
kubectl exec <pod-name> -- ping -c 3 -M do -s 1472 <destination-pod-ip>
```
* If ping succeeds with small sizes (e.g. `-s 1300`) but fails at standard size (`-s 1472`), the CNI MTU size exceeds the physical network packet limits.

### Resolution
Modify the Calico CNI MTU size. Edit the Calico ConfigMap:
```bash
kubectl edit configmap calico-config -n kube-system
```
Find the `veth_mtu` setting and reduce it (e.g. set it to `1450` for VXLAN or `1480` for IP-in-IP). Restart the calico-node daemonset pods to apply:
```bash
kubectl rollout restart daemonset calico-node -n kube-system
```

---

## 3. Network Policy blocks Traffic Silently

### Symptoms
* Pods suddenly cannot communicate after deploying updates.
* No error messages appear; connections just time out.

### Diagnosis
1. Identify if any active Network Policies select the target Pods:
```bash
# List all policies and their target selectors
kubectl get netpol -A
```
2. Inspect the target Pod to confirm it is selected:
```bash
kubectl describe pod <target-pod>
```
Look for `Isolation: Ingress` or `Isolation: Egress`. If it is isolated, a Network Policy has selected this pod, and a **default deny** rule is in effect. Any traffic not explicitly allowed in a policy is dropped.

### Resolution
Create an explicit ingress rule whitelisting the source pod labels. Verify policy selectors:
```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: authorized-source-app
```

---

## 4. CNI IP Address Exhaustion

### Symptoms
* Pods are stuck in `ContainerCreating` state.
* `kubectl describe pod` events show: `Failed to allocate IP address: CNI IPAM pool exhausted`.

### Diagnosis
Verify the status of Calico's IPAM allocations:
```bash
# Install calicoctl tool or run within calico-node container
kubectl exec -n kube-system daemonset/calico-node -c calico-node -- calicoctl ipam show --show-blocks
```
Identify if a node has locked an entire block of IPs while running very few containers.

### Resolution
If your host subnet is full, you must define an additional IPPool with a different CIDR block:
```yaml
apiVersion: projectcalico.org/v3
kind: IPPool
metadata:
  name: extra-ippool
spec:
  cidr: 10.245.0.0/16
  blockSize: 26
  ipipMode: Always
  natOutgoing: true
```
Apply the new pool:
```bash
kubectl apply -f extra-ippool.yaml
```

---

## 5. Calico Node DaemonSet CrashLoopBackOff

### Symptoms
* Pods like `calico-node-xxxxx` crash.
* Logs show BGP peering error: `BGP peering connection refused` or `Interface is not ready`.

### Diagnosis
Query the calico-node logs:
```bash
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100
```
Look for interface matching errors, such as: `Failed to autodetect IPv4 address: multiple matching interfaces found`.

### Resolution
By default, Calico tries to autodetect the host's primary interface, but it can fail if the node has multiple virtual interfaces (e.g. from Docker or bridges). Force interface autodetection using a regex match inside the `calico-node` DaemonSet environment config:
```bash
kubectl edit daemonset calico-node -n kube-system
```
Add the environment variable `IP_AUTODETECTION_METHOD`:
```yaml
- name: IP_AUTODETECTION_METHOD
  value: "interface=eth0,enp.*"
```

---

## 6. Overlay Routing Network Failures

### Symptoms
* Ping between nodes works on physical IPs.
* Ping between Pods fails on overlay IPs (`10.244.x.x`).

### Diagnosis
Verify the state of the overlay interfaces (`vxlan.calico` or `tunl0`) on the hosts:
```bash
# Execute on worker node host
ip link show vxlan.calico
```
Check if the interface status is `DOWN` or missing.

### Resolution
If the interface is down, check the Felix agent logs on that node:
```bash
kubectl logs -n kube-system <calico-node-pod-on-failed-node> -c calico-node | grep -i felix
```
Felix will print details if it fails to bind or write routes due to a locked kernel route table. Restarting the pod releases lock files.

---

## 7. Cross-Node Packet Loss

### Symptoms
* Frequent connection drops.
* Database synchronization packets drop periodically.

### Diagnosis
Check for host network interface packet drops:
```bash
# Execute on worker node host
ip -s link show dev eth0
```
Look at `RX errors`, `dropped`, or `overruns`. If errors are high, the physical network adapter queue is saturated.

### Resolution
* Enable **Flow Control** on host adapters.
* Increase ring buffer sizes using `ethtool`:
  ```bash
  ethtool -G eth0 rx 4096 tx 4096
  ```

---

## 8. Service Communication Issues (VIP Failures)

### Symptoms
* Pod-to-Pod communication via IP succeeds.
* Pod-to-Service communication via Service IP (ClusterIP) fails.

### Diagnosis
Verify if `kube-proxy` is writing translation rules correctly:
```bash
# Check if the ClusterIP exists
kubectl get svc <service-name>

# Check if kube-proxy endpoints match active Pods
kubectl get endpoints <service-name>
```
If endpoints list is empty, check the Pod's readiness probes. If readiness probes fail, the Pod is removed from the endpoint list, blocking all service routing.

### Resolution
If readiness probes are healthy but VIP routing still fails, inspect host IPVS tables (if running in IPVS mode):
```bash
# Execute on host
ipvsadm -ln -t <service-vip>:port
```
If rules are missing, restart `kube-proxy`:
```bash
kubectl rollout restart daemonset kube-proxy -n kube-system
```

---

## 9. DNS Resolution Issues (CoreDNS Failures)

### Symptoms
* Resolving external names or internal services fails (`Temporary failure in name resolution`).
* DNS queries timeout.

### Diagnosis
Inspect CoreDNS deployment health:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```
If running, check logs:
```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100
```
Check if CoreDNS is failing to reach the upstream nameserver configured in `/etc/resolv.conf`.

### Resolution
If CoreDNS is healthy but blocked, check if a global Network Policy is blocking egress to port `53` (UDP/TCP) in the client Pod's namespace (see Lab 2). Ensure all client namespaces have a policy permitting egress to DNS endpoints.

---

## 10. IP Address Conflicts inside the Cluster

### Symptoms
* Packets get routed to the wrong container.
* Connections drop randomly, or logs show traffic belonging to a different customer.

### Diagnosis
This happens if Calico's database falls out of sync with the Kubernetes API, causing IPAM to re-allocate an IP address that is still bound to a running container.
Audit for duplicate IP allocations:
```bash
kubectl get pods -A -o custom-columns=NAME:.metadata.name,IP:.status.podIP | sort | uniq -d
```

### Resolution
If a duplicate is found, delete the conflicting Pods to force container recreation and trigger CNI to request a fresh IP:
```bash
kubectl delete pod <conflicting-pod> --grace-period=0 --force
```
Verify the IPAM pool sync:
```bash
kubectl exec -n kube-system daemonset/calico-node -c calico-node -- calicoctl ipam release --ip=<conflicting-ip>
```
