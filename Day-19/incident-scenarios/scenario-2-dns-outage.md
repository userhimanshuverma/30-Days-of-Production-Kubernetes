# 🚨 Incident Scenario 2: The Silent DNS Resolution Blackout
**Severity:** Sev0 (Critical Cluster-Wide Outage)  
**MTTR:** 28 Minutes  
**Impact:** Intermittent failures in internal microservice discovery and external API calls.

---

## 1. Alerting & Symptoms
At `09:15:00 UTC`, multiple microservices trigger alerts:
```text
[CRITICAL] Service frontend: api_payment_call_failures > 5% (current: 40%)
[CRITICAL] Service order-processor: connection_timeouts to auth-service > 10%
```
SREs observe that services are failing to talk to each other, but the pods are running healthily.

---

## 2. Incident Timeline & Investigation

### 09:18 - Triage Phase
SRE runs diagnostic DNS check from a running frontend pod:
```bash
kubectl exec -it deployment/frontend-api -- nslookup auth-service.default.svc.cluster.local
```
**Output:**
```text
;; connection timed out; no servers could be reached
```
SRE checks if the CoreDNS pods are running:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```
**Output:**
```text
NAME                       READY   STATUS    RESTARTS   AGE
coredns-78f57c578f-abc12   1/1     Running   0          40d
coredns-78f57c578f-def34   1/1     Running   3          40d
```
Note that one CoreDNS pod restarted 3 times recently.

### 09:22 - CoreDNS Logs Inspection
The SRE pulls logs from the CoreDNS deployment:
```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100
```
**Output:**
```text
[WARNING] plugin/loop: Loop detected in system, DNS queries may loop back.
[ERROR] plugin/errors: 2 api.stripe.com. A: read udp 10.244.0.12:4321->192.168.1.1:53: i/o timeout
[WARNING] plugin/health: CoreDNS is not healthy. Liveness probe failed.
```
CoreDNS is logging UDP timeouts to the upstream DNS server (`192.168.1.1`) and is failing its own health check.

### 09:25 - Deep Analysis
The cluster experienced a burst of outbound requests during a marketing campaign.
Because the default `ndots:5` settings exist in all pod specifications, every query for Stripe or any external endpoint resulted in 4 queries hitting CoreDNS before hitting the upstream server. This combined search-path amplification (~40,000 queries per second) exhausted UDP socket buffers, causing packet drops.

---

## 3. Root Cause Analysis (5 Whys)

1. **Why did internal service discovery fail?** CoreDNS pods were unresponsive and restarting.
2. **Why?** CoreDNS was marked unhealthy because the liveness probe failed due to request queuing.
3. **Why did queries queue?** UDP sockets were dropping packets due to socket buffer exhaustion under a massive traffic spike.
4. **Why did traffic spike so high?** The `ndots:5` default search path caused a 4x query multiplier for every external API request.
5. **Why were there so many external queries?** The marketing campaign triggered massive concurrent external callouts, and local caching was not configured.

---

## 4. Mitigation & Resolution
*   **09:30 UTC:** SRE scales CoreDNS replicas from 2 to 6:
    ```bash
    kubectl scale deployment coredns -n kube-system --replicas=6
    ```
*   **09:35 UTC:** SRE patches the upstream config Corefile to include DNS caching rules (`cache 30` to cache responses for 30s):
    ```bash
    kubectl edit configmap coredns -n kube-system
    ```
*   **09:38 UTC:** DNS timeouts drop to zero, CoreDNS health checks pass, and system recovers.

---

## 5. Prevention Action Items
*   **NodeLocal DNS:** Deploy `NodeLocal DNSCache` daemonset to intercept queries on individual worker nodes, bypassing CoreDNS ClusterIP for most local/cached queries.
*   **Autoscaling:** Install `cluster-proportional-autoscaler` for CoreDNS to automatically scale replicas based on cluster node and core counts.
*   **Microservice Hardening:** Mandate trailing dots in external API config URLs (e.g. `api.stripe.com.`) to skip the search path loop.
