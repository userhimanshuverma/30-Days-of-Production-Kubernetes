# 📖 Day 10 Core Concepts — Ingress & Traffic Routing

Welcome to the architectural deep dive into **Kubernetes Ingress and Traffic Routing**. In this note, we will tear down how external network packets cross the boundary of a Kubernetes cluster, how they are parsed, routed, and forwarded by a reverse proxy, and how to scale this traffic path to millions of requests per second.

---

## 1. Why Ingress Exists: The Service Limitation

To understand Ingress, we must address the fundamental limitation of standard Kubernetes Services:

### The LoadBalancer Service Bottleneck
In Day 5 (Services & Load Balancing), we learned that to expose an application externally in cloud environments (like AWS, Azure, or GCP), we declare a Service of `type: LoadBalancer`.
When you deploy a LoadBalancer Service, the cloud controller manager provisions a physical cloud load balancer (such as an AWS Network Load Balancer). 

While this works, it introduces severe bottlenecks at scale:
1. **Cost Inefficiency**: Every Service of `type: LoadBalancer` gets its own dedicated cloud load balancer. If you have 50 microservices, you will provision 50 cloud load balancers. At ~$20/month per load balancer (minimum, plus traffic costs), this costs over **$1,000/month** just for routing!
2. **IP Exhaustion**: Each load balancer consumes a public IPv4 address. Large enterprises with hundreds of services can run into cloud IP quota limits.
3. **No Layer 7 Intelligence**: Cloud Network Load Balancers operate at Layer 4 (TCP/UDP). They cannot inspect HTTP headers, request paths, cookie sessions, or HTTP methods. Therefore, you cannot easily do path-based routing (e.g., routing `example.com/api` to one pod and `example.com/web` to another) using Layer 4 Services.
4. **Decentralized Security**: TLS termination (SSL certificates) must be configured individually for each load balancer, complicating key rotation and compliance audits.

### Enter Ingress (Layer 7 Routing)
Kubernetes `Ingress` is an API resource that provides a **consolidated HTTP/S entry point** (Layer 7) into the cluster. It allows you to define routing rules (domain name hosts, path prefixes) that consolidate all external traffic through a **single cloud load balancer** pointing to an **Ingress Controller**.

```
[ Client Traffic ]
       │
       ▼ (Single External IP / DNS)
┌──────────────┐
│  Cloud LB    │  <-- Only ONE cloud load balancer (minimizes cost!)
└──────┬───────┘
       │ (Port 80/443)
       ▼
┌──────────────┐
│ Ingress Pods │  <-- Layer 7 Reverse Proxy (inspects HTTP Host & Path)
└─┬──────────┬─┘
  │          │
  │ /api     │ /static
  ▼          ▼
┌────────┐ ┌────────┐
│Svc API │ │Svc Web │  <-- Internal ClusterIP Services
└────────┘ └────────┘
```

---

## 2. Reverse Proxy & Edge Networking

At its core, an Ingress Controller acts as an edge **Reverse Proxy**. Let's review the mechanics:

### Forward Proxy vs. Reverse Proxy
* **Forward Proxy**: Acts on behalf of a **client** to access external servers (e.g., an enterprise web filter or VPN that hides the client's identity).
* **Reverse Proxy**: Acts on behalf of the **servers** to handle client requests (e.g., Ingress NGINX). The client has no direct visibility into the backend pods; it only talks to the proxy.

### Request Proxying & Header Mutation
When a client sends an HTTP request, the reverse proxy intercepts the TCP connection, performs TLS decryption, inspects the headers, and initiates a **new TCP connection** to the backend Pod (bypassing the Service IP for performance - more on this later).

Because the proxy creates a new request to the pod, the pod's application code would see the connection originating from the proxy's IP, not the client's. To preserve client metadata, the proxy mutates the request headers before forwarding it:

| Header | Purpose | Example |
| :--- | :--- | :--- |
| `Host` | Identifies which domain the client requested (critical for host-based routing). | `Host: academy.internal` |
| `X-Real-IP` | Captures the raw IP address of the client browser. | `X-Real-IP: 198.51.100.42` |
| `X-Forwarded-For` | A list of IPs tracing the routing path. Each proxy appends the client IP it received. | `X-Forwarded-For: 198.51.100.42, 10.0.1.10` |
| `X-Forwarded-Proto` | Tells the backend what protocol the client used (`http` or `https`). | `X-Forwarded-Proto: https` |
| `X-Request-ID` | A unique UUID injected by the proxy to enable end-to-end distributed tracing. | `X-Request-ID: c542b87f-94d3` |

---

## 3. NGINX Ingress Controller Architecture

The NGINX Ingress Controller is one of the most widely used ingress implementations. It runs as a Go application wrapping an NGINX reverse proxy. It is split into two components: the **Control Plane** and the **Data Plane**.

```
┌────────────────────────────────────────────────────────┐
│                Kubernetes API Server                   │
└──────────────────────────▲─────────────────────────────┘
                           │ Watch Events (Endpoints, Ingress, Secrets)
┌──────────────────────────▼─────────────────────────────┐
│                 CONTROL PLANE (Go Daemon)              │
│  - Runs a controller loop.                             │
│  - Receives K8s resource changes.                      │
│  - Renders nginx.conf template.                        │
│  - Updates OpenResty/Lua memory tables.                │
└──────────────────────────┬─────────────────────────────┘
                           │ Injects configuration
                           ▼
┌────────────────────────────────────────────────────────┐
│                 DATA PLANE (NGINX / OpenResty)         │
│  - Receives HTTP/S client traffic on 80/443.           │
│  - Terminates TLS using certs stored in memory.        │
│  - Executes Lua scripts for dynamic routing.           │
│  - Forwards packets directly to Pod IPs.               │
└────────────────────────────────────────────────────────┘
```

### The Control Plane (Go Controller Loop)
The control plane is a Go binary that runs inside the Ingress Controller pod. It does not process client traffic. Instead:
1. It uses **K8s Informers** to watch the Kubernetes API server for changes to `Ingress` resources, `Services`, `Endpoints`, and `Secrets`.
2. When a change is detected, it reconciles the state.
3. In older ingress architectures, the Go controller would write a new `nginx.conf` file to disk and execute `nginx -s reload`. However, NGINX reloads discard keep-alive connections and incur CPU overhead, which can cause traffic drops during rapid scaling.
4. Modern NGINX controllers use **OpenResty (Lua)** to dynamically update backends in memory without reloading the NGINX master process!

### The Data Plane (NGINX / OpenResty Engine)
The data plane is the NGINX engine itself. It binds ports `80` (HTTP) and `443` (HTTPS) to receive client packets. 
* It intercepts the TLS handshake and extracts the hostname via **SNI (Server Name Indication)**.
* It evaluates the request using the compiled routing tree.
* It selects the target Pod IP from its internal endpoint list (cached in Lua memory) and forwards the request.

---

## 4. Connection & Buffer Tuning

Operating Ingress at scale requires balancing memory usage against TCP throughput:

### Keep-Alive Sizing
HTTP Keep-Alive allows reusing TCP connections for multiple HTTP requests, saving the CPU cost of negotiating 3-way handshakes:
* **Client Keep-Alive** (`keep-alive-requests`): In production, set this high (e.g., `10000`). If clients (browsers, external mobile apps) make multiple API requests, they should reuse the TLS/TCP connection.
* **Upstream Keep-Alive** (`upstream-keepalive-connections`): Ingress NGINX can maintain a pool of warm TCP connections to backend pods. This is critical in high-throughput microservice clusters, reducing socket allocation times and CPU usage in the backend application.

### Buffer Tuning
When NGINX receives requests, it stores headers and request bodies in memory buffers before sending them to the backend:
* `client_header_buffer_size` (Default: `1k`): Sized to hold typical HTTP request headers. Large headers (e.g., JWT tokens or cookies) might require increasing this to `4k` or `8k` to avoid `414 Request-URI Too Large` or `400 Bad Request` errors.
* `client_body_buffer_size` (Default: `8k`/`16k`): If a POST payload fits in this buffer, NGINX keeps it in RAM. If the payload is larger, NGINX writes it to a temporary file on disk, which drastically slows down API throughput. For image upload APIs or bulk JSON, increase this buffer or set it via Ingress annotations.

---

## 5. TLS Termination vs. Passthrough

Kubernetes Ingress controllers handle encryption at the cluster boundary in two ways:

```
[ Client ] === (Encrypted: HTTPS) ===> [ Ingress Proxy ] === (Plaintext: HTTP) ===> [ Pod ]
                                       * Decrypts TLS here (TLS Termination)

[ Client ] =================== (Encrypted: HTTPS) ==============================> [ Pod ]
                                       * Proxy passes raw encrypted bytes (TLS Passthrough)
```

### TLS Termination (Most Common)
1. **How it works**: The client initiates an SSL handshake with the Ingress Controller. The Ingress Controller uses a certificate from a Kubernetes `Secret` to decrypt the traffic. The connection from the Ingress Controller to the backend pod is sent over plaintext HTTP.
2. **Advantages**:
   * CPU-intensive decryption is offloaded to the Ingress controller, keeping application pods lightweight.
   * Centralized certificate management (e.g. automated certificate rotation via Cert-Manager).
   * Simple ingress rule evaluation (since NGINX can inspect the decrypted headers and path strings).

### TLS Passthrough
1. **How it works**: The Ingress Controller does not decrypt the traffic. It inspects the SNI header in the TLS client handshake (which is unencrypted) to find the target hostname, and then proxies the raw TCP packet stream directly to the backend pod. The pod itself terminates the SSL connection.
2. **Advantages**:
   * End-to-end encryption. The Ingress controller never sees the decrypted payload. Essential for strict compliance environments (HIPAA, PCI-DSS) where decryption keys cannot exist on intermediate proxies.
3. **Disadvantages**:
   * You cannot perform path-based routing (since the path is encrypted).
   * High CPU cost on application pods.

---

## 6. Routing Strategies in Production

Ingress controllers support three primary Layer 7 routing patterns:

### I. Host-Based Routing
Matches the HTTP `Host` header. This allows hosting multiple independent domains or subdomains on a single IP:
* `academy.internal` -> routes to `frontend-svc`
* `api.academy.internal` -> routes to `order-api-svc`

### II. Path-Based Routing
Routes traffic matching specific sub-paths under the same domain name:
* `academy.internal/` -> routes to `frontend-svc`
* `academy.internal/api/v1/orders` -> routes to `order-api-svc`
* `academy.internal/api/v1/users` -> routes to `user-api-svc`

#### Regex rewrites
Many application microservices expect API requests relative to the root (`/`) rather than the nested prefix (`/api/v1/orders`). Ingress NGINX leverages rewrite annotations to strip prefix components:
* Request: `GET academy.internal/api/v1/orders/healthz`
* Rewrite rule: `nginx.ingress.kubernetes.io/rewrite-target: /$2`
* Forwarded Request: `GET order-api-svc/healthz`

### III. Wildcard Routing
Routes traffic matching wildcard hostnames:
* `*.academy.internal` -> can route requests dynamically to tenant-specific services or a shared frontend.

---

## 7. Real-World Production Examples

### Case 1: The E-Commerce Platform
An e-commerce app requires public traffic to access a static storefront, a checkout API, and a customer account page.
* **Storefront (Static)**: Path `/` -> `frontend-svc` (Port 80)
* **Checkout API (High Security)**: Path `/checkout` -> TLS Termination -> `checkout-svc` (Port 443, SSL/TLS backend connection)
* **Search Catalog (Dynamic)**: Path `/search` -> `search-svc` (Port 80, aggressive caching headers injected at NGINX)

### Case 2: API Gateway Pattern
Consolidating external API endpoints. An external gateway host `api.prod.internal` splits requests:
* `/v1/auth` -> `identity-service`
* `/v1/payments` -> `payment-service` (with dedicated rate-limiting annotations on Ingress to prevent DDOS)
* `/v1/telemetry` -> `telemetry-service` (large proxy buffers enabled to support heavy upload payloads)
