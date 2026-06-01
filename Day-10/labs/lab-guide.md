# 🛠️ Hands-On Lab Walkthrough: Config Ingress & Routing

This lab walks you through setting up a Kubernetes cluster locally, installing the NGINX Ingress Controller, deploying backend services, configuring host-based and path-based routing, and securing the traffic using self-signed TLS certificates.

---

## Prerequisites
* **Docker** installed and running on your machine.
* **kubectl** CLI installed.
* **kind** (Kubernetes in Docker) CLI installed. Alternatively, you can use Minikube, but this guide is customized for Kind to bind local ports `80` and `443`.

---

## Step 1: Create a Kind Cluster with Port Mapping
By default, Kind runs inside a Docker container. To access our Ingress Controller on localhost ports `80` and `443`, we must create a cluster configuration that exposes these host ports to the Kind container.

Create a file named `kind-config.yaml` in your scratch directory or current path:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    apiVersion: kubeadm.k8s.io/v1beta3
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
```

Now, spin up the cluster using the config:
```bash
kind create cluster --config kind-config.yaml --name ingress-lab
```

---

## Step 2: Install NGINX Ingress Controller
With the cluster running, install the official NGINX Ingress Controller configured for Kind. This manifest includes patches that allow NGINX to bind to ports `80` and `443` on the node:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

Wait for the ingress controller pods to become ready (this may take up to a minute):
```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

Verify that the Ingress controller service is running and listening:
```bash
kubectl get pods -n ingress-nginx
```

---

## Step 3: Deploy Backend Services
Apply the backend application deployments and services:

```bash
kubectl apply -f manifests/01-backends.yaml
```

**Expected Output**:
```text
deployment.apps/frontend created
service/frontend-svc created
deployment.apps/order-api created
service/order-api-svc created
deployment.apps/user-api created
service/user-api-svc created
```

Check the status of the pods:
```bash
kubectl get pods -n default
```
Make sure all pods (`frontend-*`, `order-api-*`, `user-api-*`) are `Running` and `2/2` or `1/1` ready.

---

## Step 4: Configure Host and Path-Based Routing
Deploy the Ingress resource containing the host/path rules and rewrite patterns:

```bash
kubectl apply -f manifests/02-ingress-routing.yaml
```

**Expected Output**:
```text
ingress.networking.k8s.io/main-ingress created
```

Verify the ingress resource:
```bash
kubectl get ingress main-ingress
```

---

## Step 5: Test Routing Rules without Local DNS Hacks
Because `academy.internal` is a dummy domain, your machine doesn't know how to resolve it to `127.0.0.1` by default. Instead of modifying your `/etc/hosts` file, you can pass the `Host` header manually using `curl`.

### 1. Test Static Frontend
```bash
curl -i -H "Host: academy.internal" http://localhost/
```
**Expected Output**:
You should see a `200 OK` response returning the default NGINX HTML index file (`Server: nginx/1.25.x-alpine`).

### 2. Test Path-Based Routing (Order API)
```bash
curl -i -H "Host: academy.internal" http://localhost/api/v1/orders/healthz
```
**Expected Output**:
```text
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain; charset=utf-8
Content-Length: 64

{"status":"ok","service":"order-api","version":"v1.0.0"}
```
*Take note of the response body. NGINX successfully stripped `/api/v1/orders` and forwarded `/healthz` to the backend.*

### 3. Test Path-Based Routing (User API)
```bash
curl -i -H "Host: academy.internal" http://localhost/api/v1/users/healthz
```
**Expected Output**:
```text
HTTP/1.1 200 OK
Server: nginx
Content-Type: text/plain; charset=utf-8

{"status":"ok","service":"user-api","version":"v1.0.0"}
```

### 4. Test API Gateway Host Routing
```bash
curl -i -H "Host: api.academy.internal" http://localhost/orders
```
*This resolves to the order-api because we are hitting the `api.academy.internal` host rule.*

---

## Step 6: Generate and Enable TLS
Now, let's configure SSL/TLS encryption.

### 1. Generate SSL Certificates
Use OpenSSL to generate a self-signed key and certificate for `academy.internal`:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout academy.key \
  -out academy.crt \
  -subj "/CN=academy.internal/O=Academy" \
  -addext "subjectAltName = DNS:academy.internal,DNS:api.academy.internal"
```

### 2. Create the Kubernetes Secret Manually
Delete the mock secret (if deployed) and create the TLS secret with your real certificate files:
```bash
kubectl delete secret academy-tls-secret --ignore-not-found
kubectl create secret tls academy-tls-secret \
  --cert=academy.crt \
  --key=academy.key
```

### 3. Apply the TLS Ingress Configurations
```bash
kubectl apply -f manifests/03-ingress-tls.yaml
```

### 4. Test the TLS Connection
Using `curl` with the `--insecure` (or `-k`) flag to trust our self-signed certificate:
```bash
curl -ivk -H "Host: academy.internal" https://localhost/
```

**Verify the Handshake Logs**:
Review the verbose curl output. You should observe:
* Client requesting TLS handshake on `localhost:443`.
* Server presenting the certificate with `/CN=academy.internal`.
* NGINX terminating TLS and returning the HTML content.

---

## Step 7: Inspect Controller Logs
Open a separate terminal window and inspect the controller logs in real-time to watch requests:

```bash
kubectl logs -f -n ingress-nginx \
  -l app.kubernetes.io/component=controller --tail=20
```

Trigger requests using the curl commands in Step 6 and watch NGINX output access logs displaying the request path, status code, and upstream pod IP addresses.
