# 🧪 Lab 4: Resolve DNS Failures

## Objective
Learn how to identify and resolve name resolution (DNS) issues in Kubernetes pods due to misconfigured DNS policies.

## Broken Environment
We will use the manifest [dns-resolution-broken.yaml](../manifests/dns-resolution-broken.yaml) which deploys a client pod that cannot resolve cluster-local services because its custom `dnsConfig` overrides the default cluster CoreDNS configuration.

---

## Step-by-Step Investigation

### 1. Apply the Broken Manifest
Apply the manifest to the cluster:
```bash
kubectl apply -f ../manifests/dns-resolution-broken.yaml
```

### 2. Verify Pod Health
Check if the DNS client pod is running:
```bash
kubectl get pods dns-broken-client
```

### 3. Test Local Name Resolution
Try to resolve the cluster-local service `kubernetes.default.svc.cluster.local` from inside the client pod:
```bash
kubectl exec -it dns-broken-client -- nslookup kubernetes.default.svc.cluster.local
```

**Expected Output:**
```text
Server:		8.8.8.8
Address:	8.8.8.8#53

** server can't find kubernetes.default.svc.cluster.local: NXDOMAIN
command terminated with exit code 1
```
*Note that the query is hitting nameserver `8.8.8.8` instead of the internal CoreDNS server. External servers cannot resolve internal cluster services.*

### 4. Inspect `/etc/resolv.conf`
Read the DNS configuration file inside the pod:
```bash
kubectl exec -it dns-broken-client -- cat /etc/resolv.conf
```

**Expected Output:**
```text
nameserver 8.8.8.8
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```
The nameserver is overridden by `8.8.8.8`, which breaks default Cluster-First resolution.

---

## Resolution Walkthrough

To fix local service discovery while maintaining custom search behaviors:

1. Open [dns-resolution-broken.yaml](../manifests/dns-resolution-broken.yaml).
2. Locate the `.spec.dnsPolicy` field. Currently, it is set to `None`.
3. Change it to `ClusterFirst` (or remove the line since `ClusterFirst` is the default).
4. Remove the `dnsConfig.nameservers` block so that the Kubelet automatically injects the CoreDNS service IP.
5. Re-apply the manifest:
   ```bash
   kubectl apply -f ../manifests/dns-resolution-broken.yaml
   ```
6. Verify the pod is recreated and tests succeed:
   ```bash
   # Wait for recreation and run:
   kubectl exec -it dns-broken-client -- nslookup kubernetes.default.svc.cluster.local
   ```
   **Expected Output:**
   ```text
   Server:		10.96.0.10
   Address:	10.96.0.10#53

   Name:	kubernetes.default.svc.cluster.local
   Address: 10.96.0.1
   ```
   *The name now resolves successfully using the CoreDNS nameserver.*
