# 🛠️ Lab 4: Testing DNS Resolution Internals

In this lab, you will inspect the DNS configuration inside a running Pod, trace the resolution steps for both internal and external hostnames, and analyze how CoreDNS search domains operate.

---

## Step 1: Inspect `/etc/resolv.conf`
Exec into the `dns-debug` container and read the DNS configuration file:

```bash
kubectl exec -it dns-debug -- cat /etc/resolv.conf
```

**Expected Output**:
```text
nameserver 10.96.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5
```

* **nameserver**: This matches the ClusterIP of the `kube-dns` Service inside the `kube-system` namespace. Let's verify:
  ```bash
  kubectl get svc kube-dns -n kube-system
  ```
* **search**: Suffixes appended to queries containing fewer than `ndots` dots.
* **ndots:5**: The threshold for relative vs. absolute DNS lookups.

---

## Step 2: Query CoreDNS for an Internal Service
Run a query for our internal backend service:
```bash
kubectl exec -it dns-debug -- nslookup web-backend-service
```

**Expected Output**:
```text
Server:         10.96.0.10
Address:        10.96.0.10#53

Name:   web-backend-service.default.svc.cluster.local
Address: 10.96.14.22
```

Notice the resolved FQDN (Fully Qualified Domain Name): `web-backend-service.default.svc.cluster.local`. CoreDNS returned the service's ClusterIP.

Now try querying with the FQDN directly:
```bash
kubectl exec -it dns-debug -- nslookup web-backend-service.default.svc.cluster.local
```

This resolves instantly because it matches the exact FQDN format.

---

## Step 3: Observe DNS Resolution for External Domains
Now let's resolve an external address:
```bash
kubectl exec -it dns-debug -- nslookup google.com
```

**Expected Output**:
```text
Server:         10.96.0.10
Address:        10.96.0.10#53

Non-authoritative answer:
Name:   google.com
Address: 142.250.190.46
```

While this lookup completes successfully, behind the scenes the client resolver made 5 separate queries because of `ndots:5`. Let's prove it by querying with a trailing dot:

```bash
# Force absolute query (skips search paths)
kubectl exec -it dns-debug -- nslookup google.com.
```

By appending a trailing dot, the client resolver immediately skips the search suffix checks and forwards the query directly to CoreDNS, which resolves it upstream instantly. This simple optimization can significantly reduce CoreDNS load in high-traffic applications making external API calls.
