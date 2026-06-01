# ⚡ Production Considerations & Lessons Learned: Kubernetes Ingress at Scale

Operating Kubernetes Ingress in production is vastly different from running it in a sandbox. In high-traffic systems, the Ingress controller is the single most critical component in the data path—if Ingress goes down, the entire system is inaccessible.

This guide compiles senior-level engineering observations and best practices from operating large-scale ingress infrastructure at major cloud providers.

---

## 1. High Availability (HA) & Topology Design

Never run a single replica of your Ingress Controller in production. A single node failure or node upgrade will cause an outage.

### Deployment Topologies
* **DaemonSet Mode (Recommended for Bare-Metal/Direct Edge)**: Runs one Ingress Pod on every designated worker node. Good for predictable resources and minimizing network hops.
* **Deployment Mode (Recommended for Cloud Providers)**: Runs as a Deployment scaled by Horizontal Pod Autoscalers (HPA). 

### Pod Anti-Affinity
To ensure high availability, enforce **Pod Anti-Affinity** to guarantee that Ingress controller replicas are scheduled across different worker nodes and different Availability Zones (AZs):

```yaml
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: Ingress
            values:
            - ingress-nginx
        topologyKey: topology.kubernetes.io/zone # Spread across AZs
```

### Pod Topology Spread Constraints
Alternatively, use `topologySpreadConstraints` to enforce an even balance of replicas across zones to prevent a single zone outage from degrading more than $1/N$ of your capacity.

---

## 2. Ingress Scaling & CPU Throttling

### The CFS Quota Trap (CPU Throttling)
In Kubernetes, setting CPU limits on CPU-bound networking pods like NGINX can lead to severe latency spikes. NGINX processes requests using single-threaded worker processes. When a burst of requests arrives, CPU usage spikes briefly. If your CPU limit is set too low, the Linux **Completely Fair Scheduler (CFS)** will throttle the pod's CPU cycles mid-request.
* **Symptom**: Spikes in latency (e.g. requests jumping from 5ms to 100ms+) and connection drops under moderate load.
* **Mitigation**: In production, consider **omitting CPU limits** for Ingress pods while setting generous **CPU requests** (e.g., `requests.cpu: "2"` or `"4"`), and let the scheduler place them on nodes with headroom. Alternatively, disable CFS quota limits on the kubelet if supported.

### Autoscaling Metrics
Scale Ingress pods based on custom metrics rather than CPU alone:
* **Connections / Requests per Second (RPS)**: Use Prometheus metrics adapted for HPA to scale out before memory/CPU saturation.
* **Active Connections**: A high connection count drains available file descriptors and ephemeral ports on the host node.

---

## 3. Preserving Client IP (`externalTrafficPolicy: Local`)

When client traffic passes through a Cloud Load Balancer to a worker node, the node might forward the traffic to an Ingress Pod running on a *different* worker node. This host-hop performs **SNAT (Source Network Address Translation)**, causing NGINX to see the node's internal IP instead of the client's public IP.

```
[ Client IP: 198.51.100.42 ] 
         │
         ▼
[ Cloud Load Balancer ]
         │
         ▼ (Routes to Node A)
┌──────────────────────────────────────┐
│ Worker Node A                        │
│ - No Ingress pod is running here     │
│ - Forwards packets to Node B         │
│ - Performs SNAT                      │
└────────┬─────────────────────────────┘
         │ (Internal Node IP: 10.0.1.10)
         ▼
┌──────────────────────────────────────┐
│ Worker Node B                        │
│ - Runs Ingress Pod                  │
│ - NGINX sees remote_addr: 10.0.1.10  │
└──────────────────────────────────────┘
```

### The Solution: `externalTrafficPolicy: Local`
Set `externalTrafficPolicy: Local` on your Ingress Controller's LoadBalancer Service:

```yaml
spec:
  type: Service
  externalTrafficPolicy: Local
```

**What this does**:
1. The cloud load balancer checks which worker nodes run active Ingress pods.
2. The load balancer ONLY routes external traffic directly to those nodes.
3. Because traffic is received directly on a node running the destination pod, **no SNAT occurs**, preserving the raw client IP in NGINX.
4. **Caution**: This requires running Ingress replicas on every node, or using a cloud load balancer that correctly performs health checks per node endpoint to avoid sending traffic to nodes without an Ingress replica.

---

## 4. TLS Certificate Automation & Management

Manually managing SSL certificates leads to outages. Always automate certificate provisioning and rotation.

### Cert-Manager & Let's Encrypt
Deploy `cert-manager` inside your cluster. It watches for `Ingress` resources with specific annotations (e.g. `cert-manager.io/cluster-issuer: letsencrypt-prod`) and automatically:
1. Negotiates ACME challenges (HTTP-01 or DNS-01).
2. Obtains public TLS certificates.
3. Generates the Kubernetes TLS Secret.
4. Renews the certificate 30 days before expiration.

### Wildcard Certificates
For multi-tenant systems, use **DNS-01 verification** via Cloudflare, Route53, or Google DNS. This allows provisioning a single wildcard certificate (`*.academy.internal`) which secures all paths without generating public traffic validation footprints for individual subdomains.

---

## 5. Security & DDoS Protection

Because the Ingress controller is the doorway to your cluster, it is a prime target for attacks.

### Rate Limiting Annotations
Configure local rate-limiting at the ingress level using NGINX annotations to prevent brute-force attacks:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/limit-connections: "20"
    nginx.ingress.kubernetes.io/limit-rps: "10"
```

### Web Application Firewall (WAF) Integration
Do not run complex WAF rules (like OWASP ModSecurity) directly inside the NGINX Ingress Controller pods under heavy load. WAF regex inspection is CPU-heavy and can bottleneck the proxy.
* **Better Practice**: Terminate DDoS attacks and run heavy WAF rules at the **Cloud Edge** (e.g., Cloudflare, AWS WAF, GCP Cloud Armor) before the packets reach your Kubernetes cluster network.

---

## 6. Multi-Tenant Ingress Architectures

In multi-tenant clusters (where multiple teams share the same physical cluster), running a single shared Ingress Controller can lead to:
* **Noisy Neighbor Effect**: Team A's traffic spike exhausts the Ingress CPU, taking down Team B's API.
* **Security Risk**: A misconfiguration or duplicate routing path defined by Team A can intercept/hijack Team B's traffic.

### Ingress Classes
Assign distinct Ingress Controllers to different namespaces or business units:
1. Deploy separate controller installations.
2. Label them with different `ingressClassName` values:
   * `ingressClassName: internal-nginx` (for internal portals, private VPN-only)
   * `ingressClassName: public-nginx` (for client-facing public sites)
3. Ensure teams configure their Ingress resources to bind to the correct class:

```yaml
spec:
  ingressClassName: public-nginx
```
This isolates the data-plane traffic and guarantees resources to individual tenants.
