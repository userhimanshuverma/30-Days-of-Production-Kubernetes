# Lab 4: Enforce Mutual TLS (mTLS)

## Goal
Enforce strict mutual TLS (mTLS) in the default namespace and verify that unencrypted plaintext connections are blocked by the proxies.

---

## Step 1: Enforce Strict mTLS

1.  Apply the strict PeerAuthentication configuration:
    ```bash
    kubectl apply -f security/peer-authentication-strict.yaml
    ```
2.  Verify the policy status:
    ```bash
    kubectl get peerauthentication -n default
    ```

---

## Step 2: Test Plaintext Connection (Should Fail)

To simulate an attacker making connections from outside the service mesh, we will launch an un-injected temporary pod (without a sidecar proxy) and try to query the backend service.

1.  Run a temporary curl pod with sidecar injection explicitly disabled:
    ```bash
    kubectl run bypass-pod --image=curlimages/curl --rm -it --restart=Never --overrides='{"metadata":{"annotations":{"sidecar.istio.io/inject":"false"}}}' -- curl -sS -v http://backend-service:80
    ```
2.  Observe the output.
    *Expected Output:*
    ```
    *   Trying 10.96.14.250:80...
    * Connected to backend-service (10.96.14.250) port 80 (#0)
    * Empty reply from server
    * Connection #0 to host backend-service left intact
    curl: (52) Empty reply from server
    ```
    *The connection is accepted at TCP level by the Envoy proxy, but immediate validation detects the lack of a client TLS certificate. Envoy drops the connection immediately with no data returned.*

---

## Step 3: Test Mesh Connection (Should Succeed)

Now, make the same query from the `frontend-app` container, which *does* have a sidecar injected.

1.  Find the name of a frontend pod:
    ```bash
    FRONTEND_POD=$(kubectl get pod -l app=frontend-app -o jsonpath='{.items[0].metadata.name}')
    ```
2.  Execute a query from the frontend application container:
    ```bash
    kubectl exec $FRONTEND_POD -c application -- curl -s http://backend-service:80
    ```
3.  Observe the output.
    *Expected Output:*
    ```
    Backend Service V1 (Stable)
    ```
    *(The request was transparently upgraded to mTLS by the frontend sidecar, transmitted encrypted over the wire, decrypted by the backend sidecar, and forwarded to the backend application).*

---

## Step 4: Verify Certificates in the Proxy

Use `istioctl` to examine the dynamic certificates loaded by the frontend pod's sidecar:
```bash
istioctl proxy-config secret $FRONTEND_POD
```
*Observe that the `default` secret contains a valid X.509 cert chain with a valid serial number and expiration date, managed by SDS.*
