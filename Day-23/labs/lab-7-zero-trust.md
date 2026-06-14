# Lab 7: Implement Zero-Trust Networking

## Goal
Combine L4 cryptographic transport security (STRICT mTLS) with L7 application-layer authorization (AuthorizationPolicy) to implement a complete Zero-Trust architecture.

---

## The Zero-Trust Checklist
A zero-trust mesh connection validates three checks at every hop:
1.  **Transport Encryption**: Is the connection encrypted? (Enforced by PeerAuthentication).
2.  **Client Authenticated**: Does the client possess a valid cryptographic identity signed by our CA? (Enforced by mTLS certificate exchange).
3.  **Client Authorized**: Is the client's SPIFFE ID explicitly permitted to perform this action (HTTP Method + URI Path) on this service? (Enforced by AuthorizationPolicies).

---

## Step 1: Establish Namespace Sandbox

Create a dedicated secure sandbox namespace to separate zero-trust workloads.

1.  Create the namespace:
    ```bash
    kubectl create namespace secure-sandbox
    ```
2.  Enable sidecar injection:
    ```bash
    kubectl label namespace secure-sandbox istio-injection=enabled
    ```

---

## Step 2: Deploy Workloads & Services

Deploy a secure client and backend app inside the sandbox.

1.  Deploy a backend instance in the sandbox:
    ```yaml
    # secure-backend.yaml
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: secure-backend-sa
      namespace: secure-sandbox
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: secure-backend
      namespace: secure-sandbox
    spec:
      ports:
      - name: http-port
        port: 80
        targetPort: 8080
      selector:
        app: secure-backend
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: secure-backend
      namespace: secure-sandbox
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: secure-backend
      template:
        metadata:
          labels:
            app: secure-backend
        spec:
          serviceAccountName: secure-backend-sa
          containers:
          - name: app
            image: hashicorp/http-echo:latest
            args:
            - "-text=Welcome to the Secure Zone"
            - "-listen=:8080"
            ports:
            - containerPort: 8080
    ```
    Save and apply:
    ```bash
    kubectl apply -f secure-backend.yaml
    ```

2.  Deploy a secure client instance:
    ```yaml
    # secure-client.yaml
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: secure-client-sa
      namespace: secure-sandbox
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: secure-client
      namespace: secure-sandbox
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: secure-client
      template:
        metadata:
          labels:
            app: secure-client
        spec:
          serviceAccountName: secure-client-sa
          containers:
          - name: app
            image: curlimages/curl
            command: ["sleep", "3600"]
    ```
    Save and apply:
    ```bash
    kubectl apply -f secure-client.yaml
    ```

---

## Step 3: Configure Security Policies

Now apply the policies that lock down access.

1.  Apply a STRICT PeerAuthentication policy for the namespace:
    ```yaml
    apiVersion: security.istio.io/v1beta1
    kind: PeerAuthentication
    metadata:
      name: sandbox-mtls
      namespace: secure-sandbox
    spec:
      mtls:
        mode: STRICT
    ```
    Apply: `kubectl apply -f sandbox-mtls.yaml`

2.  Apply an AuthorizationPolicy permitting ONLY the `secure-client-sa` to access the backend on path `/info`:
    ```yaml
    apiVersion: security.istio.io/v1beta1
    kind: AuthorizationPolicy
    metadata:
      name: sandbox-authz
      namespace: secure-sandbox
    spec:
      selector:
        matchLabels:
          app: secure-backend
      action: ALLOW
      rules:
      - from:
        - source:
            principals: ["cluster.local/ns/secure-sandbox/sa/secure-client-sa"]
        to:
        - operation:
            methods: ["GET"]
            paths: ["/info"]
    ```
    Apply: `kubectl apply -f sandbox-authz.yaml`

---

## Step 4: Validate Zero-Trust Rules

1.  Identify the secure client pod:
    ```bash
    CLIENT_POD=$(kubectl get pod -n secure-sandbox -l app=secure-client -o jsonpath='{.items[0].metadata.name}')
    ```
2.  Verify GET request on `/info` is **successful**:
    ```bash
    kubectl exec -n secure-sandbox $CLIENT_POD -c app -- curl -s http://secure-backend/info
    # Output: Welcome to the Secure Zone
    ```
3.  Verify GET request on `/admin` is **blocked** (due to L7 AuthZ path restriction):
    ```bash
    kubectl exec -n secure-sandbox $CLIENT_POD -c app -- curl -s -o /dev/null -w "%{http_code}\n" http://secure-backend/admin
    # Output: 403
    ```
4.  Verify POST request on `/info` is **blocked** (due to L7 AuthZ method restriction):
    ```bash
    kubectl exec -n secure-sandbox $CLIENT_POD -c app -- curl -s -X POST -o /dev/null -w "%{http_code}\n" http://secure-backend/info
    # Output: 403
    ```
