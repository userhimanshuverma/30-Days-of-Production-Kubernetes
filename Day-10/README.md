# 📖 Day 10 — Ingress & Traffic Routing
### 🏷️ PHASE 2 — RUNNING REAL APPLICATIONS

Welcome to **Day 10** of the *30 Days of Production Kubernetes* course. Today, we address one of the most vital layers of cloud infrastructure operations: **How does application traffic transition from a client browser on the public internet, cross the cluster boundary, and arrive at the correct pod replica?**

By the end of today, the common question—*"Why can't I just use a LoadBalancer Service for everything?"*—will be permanently put to rest. We will break down the mechanics of the Kubernetes Ingress resource, NGINX Ingress Controller control/data-plane operations, TLS termination, path rewrites, host routing, and production traffic isolation.

---

## 🎯 Learning Objectives
By the end of today, you will be able to:
1. Explain the cost and routing limits of `LoadBalancer` Services vs. `Ingress`.
2. Trace the step-by-step request lifecycle from a DNS lookup to a container socket.
3. Contrast TLS termination with TLS passthrough and identify security implications.
4. Deploy and verify host-based and path-based Ingress routing (with URL rewrites).
5. Tune NGINX connection Keep-Alives and proxy buffer sizes for high throughput.
6. Diagnose common routing failures (404s, 503s, TLS handshake errors, and redirect loops).

---

## 🗺️ The Unified Traffic Entry Blueprint

Below is the conceptual path that packets follow as they traverse the networking layers:

```
[ Client Request ]
       │
       ▼ (1. DNS Lookup: Resolves academy.internal)
┌──────────────┐
│  Anycast DNS │ (Route53 / Cloudflare)
└──────┬───────┘
       │
       ▼ (2. Routes to Layer 4 Cloud Load Balancer)
┌──────────────┐
│   Cloud LB   │ (Single IP: 34.120.5.12 - Decouples cost from microservices!)
└──────┬───────┘
       │
       ▼ (3. Enters Cluster Node Network via NodePort)
┌──────────────────────────────────────┐
│ K8s Worker Nodes (Node IP: 10.0.1.x) │
└──────┬────────────────────────┬──────┘
       │                        │
       ▼ (Direct Pod IP routing)▼
┌──────────────────┐  ┌──────────────────┐
│ NGINX Pod 1 (AZ1)│  │ NGINX Pod 2 (AZ2)│ <-- (4. Decrypts TLS & evaluates path rules)
└─┬──────────────┬─┘  └─┬──────────────┬─┘
  │              │      │              │
  │ /api/orders  │ /    │ /api/orders  │ /
  ▼              ▼      ▼              ▼
┌──────────────┐┌──────────────┐
│Order API Pod ││Frontend Pod  │  <-- (5. Processes request in application code)
└──────────────┘└──────────────┘
```

---

## 1. Why Traffic Routing Matters

As application architectures transition from monolithic layouts to microservices, web systems face two primary traffic challenges:
1. **Dynamic Scaling**: Microservices split functionality across multiple deployable teams (frontend, order processing, account profiles). Spawning a distinct external endpoint for each service becomes unmanageable.
2. **Resource Consumption Costs**: Exposing applications directly using Layer 4 Cloud LoadBalancers allocates dedicated physical infrastructure per service. Running 100 microservices would require 100 cloud load balancers, costing thousands of dollars per month and consuming extensive public IP allocations.
3. **Control Consolidation**: Without a unified entry proxy, traffic policies like rate-limiting, WAF filtering, authentication checks, and SSL certificate rotation must be implemented individually in every microservice, increasing deployment complexity.

---

## 2. Services vs. Ingress

Kubernetes provides multiple ways to expose network traffic. Let's compare their capabilities and trade-offs:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. ClusterIP (Default)                                                      │
│    - Internal IP address reachable ONLY within the cluster network.         │
│    - Client ---> [ Cluster IP (10.96.x.x) ] ---> [ Pod ]                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. NodePort                                                                 │
│    - Opens a high-range port (30000-32767) on all Worker Node host IPs.     │
│    - Client ---> [ Node Host IP:32080 ] ---> [ Cluster IP ] ---> [ Pod ]   │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. LoadBalancer                                                             │
│    - Provisions an external cloud load balancer pointing to NodePort.       │
│    - Client ---> [ Cloud LoadBalancer IP ] ---> [ Node IP:Port ] ---> [ Pod ]│
├─────────────────────────────────────────────────────────────────────────────┤
│ 4. Ingress (Layer 7 Routing)                                                │
│    - Unified edge proxy routing traffic based on HTTP domain Host & Paths. │
│    - Client ---> [ Single Cloud LB ] ---> [ Ingress Controller ] ---> [ Pod ]│
└─────────────────────────────────────────────────────────────────────────────┘
```

* **ClusterIP**: Purely internal. Cannot be reached from the public internet.
* **NodePort**: Cheap exposure but requires exposing raw worker node IPs and managing irregular port allocations.
* **LoadBalancer**: Simple and robust, but expensive ($$$) and lacks Layer 7 URL routing capability.
* **Ingress**: Consolidates routing rules to match Host headers (`academy.internal`) and path prefixes (`/api/v1/orders`) through a single external load balancer pointing to internal ClusterIP Services.

---

## 3. Reverse Proxy Explained

An Ingress Controller is a specialized **Reverse Proxy**. 
* **The Analogy**: Think of a forward proxy as a personal assistant checking your outgoing mail (hiding your identity). Think of a reverse proxy as a receptionist at a corporate headquarters. Clients (visitors) do not walk directly into the engineers' offices (Pods). Instead, they talk to the receptionist (Ingress Proxy), who reads the visitor's destination name (Host header) or department request (Path prefix), verifies their credentials (TLS handshake), and guides them to the exact office room (Pod).

```
Client Browser  ====(HTTPS)====>  Reverse Proxy (Ingress)  ====(HTTP)====>  Backend Pods
(Wants /api)                      (Inspects Host & Path)                    (Processes /)
```

During this proxying, NGINX mutates HTTP headers to preserve client origin data, injecting headers like `X-Real-IP`, `X-Forwarded-For`, and `X-Request-ID`.

---

## 4. NGINX Ingress Controller Internals

The NGINX Ingress Controller runs as a Go application wrapping an NGINX reverse proxy engine:
* **Control Plane (Go Loop)**: A Go daemon watches the Kubernetes API server for changes to `Ingress`, `Services`, `Endpoints`, and `Secrets`. It parses these changes and converts them into configuration.
* **Data Plane (NGINX/OpenResty)**: Handles the raw client packets on ports `80` and `443`. Modern implementations use **Lua code** in OpenResty to hot-reload endpoint Pod IPs dynamically in shared memory, preventing costly configuration disk writes and NGINX worker reloads.

---

## 5. TLS Termination vs. Passthrough

Encrypting HTTP traffic (HTTPS) can be terminated at different boundaries:
* **TLS Termination (Default)**: The SSL connection is completed at the Ingress Controller. The Ingress decrypts the traffic using private keys stored in a Kubernetes `Secret`. The decrypted payload is sent in plaintext HTTP across the internal SDN overlay network to the pod. Offloads CPU encryption tasks from application pods.
* **TLS Passthrough**: The Ingress Controller does not decrypt the traffic. It reads the unencrypted Server Name Indication (SNI) host header during the TLS handshake, and forwards the raw encrypted stream to the pod. The pod must decrypt the connection. Used for high-security compliance workloads (HIPAA, PCI-DSS).

---

## 6. Real Production Examples

* **E-Commerce Routing**: Directing `/` (home storefront) to static NGINX cache servers, `/api/checkout` to payment pods, and `/api/products` to catalog services.
* **API Gateway Routing**: Providing a single hostname entry (`api.academy.internal`) that branches backend API services based on path mappings.
* **Multi-Tenant Routing**: Exposing host-isolated customer interfaces (`tenant-a.academy.internal` and `tenant-b.academy.internal`) sharing the same Ingress proxy but isolated in namespaces.

---

## 📂 Day 10 Repository Structure

Explore these detailed folders and guides to master Kubernetes Ingress & Traffic Routing:

* 📊 **[diagrams/README.md](file:///d:/30_Days_of_Production_Kubernetes/Day-10/diagrams/README.md)**: 12 high-fidelity Mermaid diagrams detailing traffic flows, request lifecycles, proxy header mutations, HA scaling, and TLS termination handshakes.
* 📝 **[notes/core-concepts.md](file:///d:/30_Days_of_Production_Kubernetes/Day-10/notes/core-concepts.md)**: Theoretical deep dive into NGINX control/data planes, Keep-Alive connection sizing, and proxy buffer parameters.
* ⚡ **[production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-10/production-notes/lessons-learned.md)**: Production guide covering high-availability topologies, CPU CFS quota throttling under load, and `externalTrafficPolicy: Local` client IP preservation.
* 🚨 **[troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-10/troubleshooting/playbook.md)**: Step-by-step diagnostic workflows for resolving 404s, 503 Unavailable, TLS warnings, and rewrite redirect loops.
* 🛠️ **[labs/lab-guide.md](file:///d:/30_Days_of_Production_Kubernetes/Day-10/labs/lab-guide.md)**: Hands-on guide showing how to create a Kind cluster with ports forwarded, install Ingress, deploy microservices, and secure the site using OpenSSL self-signed certificates.
* 📄 **[manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-10/manifests/)**: Production-grade YAML declarations:
  * [01-backends.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-10/manifests/01-backends.yaml) (API & Web server Deployments)
  * [02-ingress-routing.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-10/manifests/02-ingress-routing.yaml) (Rules matching host, paths, and NGINX path rewrites)
  * [03-ingress-tls.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-10/manifests/03-ingress-tls.yaml) (TLS and HSTS headers configuration)
  * [04-nginx-configmap.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-10/manifests/04-nginx-configmap.yaml) (ConfigMap global scaling overrides)
* 🎮 **[resources/ingress-traffic-simulator.html](file:///d:/30_Days_of_Production_Kubernetes/Day-10/resources/ingress-traffic-simulator.html)**: Interactive, single-page dark-themed simulation dashboard for real-time visualization of host/path routing, TLS decryption status, and service fault-tolerance.
* 🏆 **[exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-10/exercises/challenges.md)**: Student challenges covering Canary split routing (90/10), basic HTTP authentication on ingress, and wildcard domain configuration.
