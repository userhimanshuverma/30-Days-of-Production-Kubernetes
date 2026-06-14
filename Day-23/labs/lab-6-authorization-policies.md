# Lab 6: Configure Authorization Policies

## Goal
Enforce L7 identity-based access control inside the mesh. Allow only the `frontend-service-account` to access the backend pods, and verify that unauthorized clients or unmapped paths return `HTTP 403 Forbidden`.

---

## Step 1: Deploy Authorization Policy

Apply the security manifest configured in the `security/` directory:
```bash
kubectl apply -f security/authorization-policy.yaml
```

---

## Step 2: Test Access from Allowed Identity (Frontend)

The `frontend-app` deployment runs with the service account `frontend-service-account`, which is explicitly whitelisted in the authorization rules.

1.  Identify a frontend pod:
    ```bash
    FRONTEND_POD=$(kubectl get pod -l app=frontend-app -o jsonpath='{.items[0].metadata.name}')
    ```
2.  Send a GET request to the whitelisted API endpoint path (`/api/v1/checkout`):
    ```bash
    kubectl exec $FRONTEND_POD -c application -- curl -s -o /dev/null -w "%{http_code}\n" http://backend-service:80/api/v1/checkout
    ```
3.  Check the HTTP response status.
    *Expected Output:*
    ```
    200
    ```
    *(The request matches the allowed SA principal AND the allowed path path `/api/v1/*`, so it is permitted).*

---

## Step 3: Test Access on Blocked Paths

The policy restricts access to path `/api/v1/*`. Let's verify that a request to `/admin/metrics` is rejected even if sent by the frontend client.

1.  Send a request to `/admin/metrics`:
    ```bash
    kubectl exec $FRONTEND_POD -c application -- curl -s http://backend-service:80/admin/metrics
    ```
2.  Inspect the output.
    *Expected Output:*
    ```
    RBAC: access denied
    ```
3.  Confirm the HTTP status code:
    ```bash
    kubectl exec $FRONTEND_POD -c application -- curl -s -o /dev/null -w "%{http_code}\n" http://backend-service:80/admin/metrics
    ```
    *Expected Output:*
    ```
    403
    ```

---

## Step 4: Test Access from Unauthorized Identity

Let's test if another service account is allowed to query the backend service. We will create a temporary pod running with the default service account instead of the authorized one.

1.  Start a temporary query pod:
    ```bash
    kubectl run guest-pod --image=curlimages/curl --rm -it --restart=Never -- curl -s http://backend-service:80/api/v1/checkout
    ```
2.  Inspect the response.
    *Expected Output:*
    ```
    RBAC: access denied
    ```
    *Although the guest pod has a sidecar proxy (meaning connection mTLS was successful), its SPIFFE identity (`spiffe://cluster.local/ns/default/sa/default`) is not listed in the ALLOW rules, so Envoy blocks the request at the application boundary.*
