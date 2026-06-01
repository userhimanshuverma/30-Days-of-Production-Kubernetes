# 🏆 Day 10 Assignment & Challenges

Put your Kubernetes networking skills to the test. These challenges are designed to force you to configure advanced annotations, research NGINX behaviors, and write production-ready manifests.

---

## Challenge 1: Build a Canary Traffic Splitter (90/10)

### Background
Your development team has written a new version of the Order API (`v1.1.0`) which contains optimizations. Before routing all production users to it, you want to perform a **Canary deployment**, routing 90% of requests to the stable version (`order-api-svc`) and 10% to the new canary version (`order-api-canary-svc`).

### Task
1. Look up the official NGINX Ingress annotations for **Canary Routing**:
   * `nginx.ingress.kubernetes.io/canary`
   * `nginx.ingress.kubernetes.io/canary-weight`
2. Write two Ingress manifests:
   * `order-stable-ingress.yaml`: The default ingress that handles standard traffic for `academy.internal/api/v1/orders`.
   * `order-canary-ingress.yaml`: The canary ingress matching the **exact same host and path**, but containing the canary annotations pointing to the canary Service.
3. Test your implementation. How would you verify that approximately 1 in 10 requests lands on the canary pods?
4. **Question**: What happens if the canary service goes down? Does NGINX fail over to the stable service automatically? Explain.

---

## Challenge 2: Ingress-level HTTP Basic Authentication

### Background
Your staging backend metrics panel is exposed at `academy.internal/metrics`. It has no built-in login portal, but you must prevent public access immediately. Instead of modifying the backend application code, you decide to configure HTTP Basic Authentication directly at the Ingress controller level.

### Task
1. Generate a basic auth credentials file using the `htpasswd` utility:
   ```bash
   htpasswd -c auth admin
   # Enter password: "k8s-is-awesome"
   ```
2. Create a Kubernetes Secret of type `Opaque` containing the base64-encoded `auth` file contents:
   ```bash
   kubectl create secret generic ingress-basic-auth --from-file=auth
   ```
3. Research and write an Ingress manifest `secure-metrics-ingress.yaml` that enforces auth. You will need these annotations:
   * `nginx.ingress.kubernetes.io/auth-type: basic`
   * `nginx.ingress.kubernetes.io/auth-secret: ingress-basic-auth`
   * `nginx.ingress.kubernetes.io/auth-realm: "Authentication Required - Admin"`
4. Apply the manifest and test access:
   ```bash
   # Should return 401 Unauthorized
   curl -i -H "Host: academy.internal" http://localhost/metrics
   
   # Should return 200 OK (with valid user/password)
   curl -i -u admin:k8s-is-awesome -H "Host: academy.internal" http://localhost/metrics
   ```

---

## Challenge 3: Secure Wildcard Routing with SNI

### Background
Your SaaS platform allows users to spin up individual instances accessible at `*.tenant.academy.internal`. You want to expose all these tenants through a single Ingress Controller using a single Wildcard TLS certificate.

### Task
1. Write a manifest for a wildcard Ingress resource.
2. The domain should match `*.tenant.academy.internal`.
3. The backend should route all matching subdomains to a shared backend dispatcher service named `tenant-router-svc` on port `8080`.
4. Configure the TLS block in the manifest to bind `*.tenant.academy.internal` to a secret named `wildcard-tenant-tls-secret`.
5. **Question**: If a client requests `client-a.tenant.academy.internal`, does NGINX forward the full requested host header to the backend pod, or does it rewrite the header to `*.tenant.academy.internal`? Why does this matter?
