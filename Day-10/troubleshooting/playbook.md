# 🚨 Troubleshooting Playbook — Ingress & Traffic Routing

This playbook contains step-by-step diagnostic procedures for solving common networking issues encountered when exposing applications using Kubernetes Ingress.

---

## 1. Diagnostics Toolbelt (Commands to Remember)

When debugging, run these core commands to isolate where the packet is failing:

```bash
# 1. Check Ingress status and IP assignment
kubectl get ingress -A

# 2. Inspect Ingress rules and event logs
kubectl describe ingress <ingress-name> -n <namespace>

# 3. View Ingress Controller controller logs (dynamic routing changes)
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -c controller --tail=100

# 4. View NGINX access/error logs (traffic proxying)
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -c controller | grep -E "WARN|ERR"

# 5. Extract and view the actual generated nginx.conf from the running controller pod
kubectl exec -n ingress-nginx -it <ingress-controller-pod-name> -- cat /etc/nginx/nginx.conf > local-nginx.conf
```

---

## 2. Troubleshooting Scenarios

### Scenario A: 404 Not Found from Ingress
* **Symptom**: Curling the domain returns `HTTP/1.1 404 Not Found` with the server header `Server: nginx`.
* **Root Cause**: The request reached the Ingress Controller, but NGINX found no matching Host rule or Path pattern in its routing tables.
* **Investigation Workflow**:
  1. Check if the Host header matches exactly. If you configure `host: academy.internal` and curl the IP directly without a host header, NGINX will serve the "Default Backend" (which returns a 404).
  2. Verify the Ingress Class. If you have multiple Ingress controllers, ensure your Ingress resource has the `ingressClassName` field set matching the controller's configured class:
     ```yaml
     spec:
       ingressClassName: nginx
     ```
  3. Validate path prefix rules. If the path type is `Exact`, a request to `/api/v1/orders/` will return a 404. Switch the rule to `pathType: Prefix`.
* **Resolution**: Align client requests with defined Host headers and path prefixes:
  ```bash
  curl -H "Host: academy.internal" http://<INGRESS_IP>/
  ```

---

### Scenario B: 503 Service Temporarily Unavailable
* **Symptom**: Client receives `HTTP/1.1 503 Service Temporarily Unavailable`.
* **Root Cause**: NGINX matched the routing rule to a Service, but the Service has no active backend Pod endpoints (all backing pods are dead or failing health checks).
* **Investigation Workflow**:
  1. Run `kubectl get endpoints <service-name>` in the namespace. If it returns `<none>`, the pods are not ready.
  2. Check pod states: `kubectl get pods -l app=<selector-label>`. If pods are in `CrashLoopBackOff` or failing readiness probes, NGINX removes them from the endpoint pool to prevent blackholing traffic.
  3. Check Service port matching. Ensure the `service.port.number` defined in the Ingress resource matches the Service's `port` field, and the Service's `targetPort` matches the container's active listening port.
* **Resolution**: Fix application startup errors or adjust probe parameters (`readinessProbe`) so pods transition to a `Ready` state.

---

### Scenario C: TLS Handshake / Certificate Errors
* **Symptom**: Curl returns `curl: (60) SSL: no alternative certificate subject name matches target host name` or browser displays `NET::ERR_CERT_AUTHORITY_INVALID`.
* **Root Cause**: The TLS certificate presented by the Ingress controller does not match the requested hostname, or the cert is expired, or it is a self-signed cert not trusted by the client.
* **Investigation Workflow**:
  1. Inspect the certificate presented by NGINX:
     ```bash
     openssl s_client -connect academy.internal:443 -servername academy.internal
     ```
  2. Check if the default "Fake Ingress Controller Certificate" is being served. This happens when NGINX cannot find the secret specified in the `tls[].secretName` block, or if the Secret is in a different namespace than the Ingress resource (Secrets must reside in the same namespace as the Ingress resource).
  3. Verify cert format. Ensure the `tls.crt` data in the Secret includes the full certificate chain (your certificate followed by intermediate CA certificates).
* **Resolution**: Deploy the Secret to the correct namespace, verify namespace matching, or configure `cert-manager` to fetch a valid public certificate.

---

### Scenario D: Path Rewrite Loops & Infinite Redirects
* **Symptom**: Browser reports `ERR_TOO_MANY_REDIRECTS`, or curl requests loop infinitely.
* **Root Cause**: The rewrite regex annotation conflicts with client requests, or NGINX is redirecting HTTP to HTTPS while an external load balancer is doing the same, creating a loop.
* **Investigation Workflow**:
  1. Check if you configured a rewrite target such as `nginx.ingress.kubernetes.io/rewrite-target: /` while matching path `path: /`. This rewrites every request to `/` and can cause infinite loops.
  2. Check if the application code itself redirects traffic (e.g., forcing HTTPS) but the Ingress controller terminates TLS and passes plaintext HTTP to the pod, causing the pod to think the request is insecure and trigger another redirect:
     ```
     [Client] ===(HTTPS)===> [Ingress] ---(HTTP)---> [Pod] ---(Redirect HTTP to HTTPS)---> [Ingress]
     ```
* **Resolution**: 
  * Use specific rewrite match groups (like `/$2` with path regex matching `/api/(.*)`).
  * Configure your application framework to recognize proxy headers (e.g., configuring Express/Rails/Django to respect `X-Forwarded-Proto`).
  * If using external SSL termination (e.g., at Cloudflare), configure NGINX SSL redirect annotations appropriately: `nginx.ingress.kubernetes.io/ssl-redirect: "false"`.

---

### Scenario E: Ingress Controller OOMKilled / CrashLoopBackOff
* **Symptom**: Ingress controller pods crash frequently.
* **Root Cause**: Memory exhaustion (Out Of Memory) or port conflicts on worker host nodes when running with `hostNetwork: true`.
* **Investigation Workflow**:
  1. Run `kubectl describe pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx` to see the exit status code. Exit code `137` indicates the pod was terminated by the OOMKiller.
  2. NGINX Ingress Controller consumes memory proportionally to the number of Ingress resources, Hosts, and Secrets in the cluster. Large multi-tenant clusters require tuning.
* **Resolution**:
  * Increase memory limits on the Ingress Controller deployment (highly active controllers often require `1Gi` to `2Gi` RAM).
  * Scope the controller to watch specific namespaces using the `--watch-namespace` argument.
