# Day 23 Service Mesh Troubleshooting Playbook

This playbook provides actionable diagnostic workflows and resolution steps for the ten most common production service mesh issues.

---

## Scenario 1: Sidecar Injection Failures
### Symptoms
Pods are scheduled and created but only show `1/1` containers instead of `2/2` (the sidecar container is missing). No error is displayed on `kubectl get pods`.

### Root Cause
1.  The namespace lacks the correct activation label (e.g., `istio-injection=enabled` or `linkerd.io/inject=enabled`).
2.  The mutating admission webhook (`istio-sidecar-injector`) is either offline, unreachable, or has certificate validation issues.
3.  The Pod spec contains overrides that explicitly disable injection (e.g., `sidecar.istio.io/inject: "false"`).

### Investigation
1.  Check namespace labels:
    ```bash
    kubectl get namespace -L istio-injection,linkerd.io/inject
    ```
2.  Inspect Pod annotations:
    ```bash
    kubectl get pod <pod-name> -o yaml | grep inject
    ```
3.  Check webhook configuration and health:
    ```bash
    kubectl get mutatingwebhookconfigurations
    kubectl get pods -n istio-system -l app=sidecar-injector
    ```
4.  Describe the ReplicaSet/Pod creation events:
    ```bash
    kubectl describe replicaset <replicaset-name>
    ```

### Resolution
1.  Apply the correct namespace label:
    ```bash
    kubectl label namespace <namespace-name> istio-injection=enabled --overwrite
    ```
2.  Restart the existing pods to trigger injection:
    ```bash
    kubectl rollout restart deployment/<deployment-name> -n <namespace-name>
    ```
3.  If the webhook is failing, check its logs:
    ```bash
    kubectl logs -n istio-system -l app=istiod
    ```

### Prevention
Integrate namespace checks into your CI/CD pipelines (e.g., validation rules in OPA Gatekeeper or Kyverno) to ensure all application namespaces are labeled.

---

## Scenario 2: mTLS Handshake Failures
### Symptoms
Workloads fail to communicate. Applications throw connection reset, SSL handshake failures, or HTTP 503 errors. Curiously, things work fine if mTLS is disabled.

### Root Cause
1.  Mismatched PeerAuthentication settings: The server is set to `STRICT` mTLS, but the client is sending plaintext (e.g., client sidecar is not injected or has an old config).
2.  Mismatched trust domains: The client and server are running in different clusters with different root certificates and no mutual trust anchor configuration.

### Investigation
1.  Check namespace security policies:
    ```bash
    kubectl get peerauthentications -A
    ```
2.  Use `istioctl` to analyze authentication mismatches:
    ```bash
    istioctl analyze -n <namespace>
    ```
3.  Inspect the certificate details on Envoy:
    ```bash
    istioctl proxy-config secret <pod-name>.<namespace>
    ```

### Resolution
1.  Change server PeerAuthentication to `PERMISSIVE` to allow migration, identify the plaintext clients, and then enforce `STRICT` once resolved:
    ```yaml
    apiVersion: security.istio.io/v1beta1
    kind: PeerAuthentication
    metadata:
      name: default
      namespace: <namespace>
    spec:
      mtls:
        mode: PERMISSIVE
    ```
2.  Inject missing client sidecars to enable mTLS negotiation.

### Prevention
Avoid implementing `STRICT` mode globally at launch. Implement a staged rollout: `DISABLE` -> `PERMISSIVE` -> Audit plaintext metrics -> `STRICT`.

---

## Scenario 3: Traffic Routing Issues
### Symptoms
Requests are not hitting the correct subset/version of a pod. For example, 100% of the traffic continues to hit the old `v1` version, even though a 50/50 split was configured.

### Root Cause
1.  The VirtualService and DestinationRule match labels are misconfigured or target missing pod labels.
2.  The client call is bypassing the mesh because it addresses the pods directly via IP instead of targeting the Kubernetes Service DNS name.
3.  The port names in the Kubernetes Service do not match the expected protocol prefix (e.g., name must start with `http-` or `grpc-` for L7 routing to work in Istio).

### Investigation
1.  Verify service port names:
    ```bash
    kubectl get svc <service-name> -o yaml
    # Look for: port.name: http (or http-web)
    ```
2.  Verify the routing rules inside Envoy:
    ```bash
    istioctl proxy-config routes <client-pod>.<namespace> --name 80 -o json
    ```
3.  Confirm DestinationRule subsets match pod labels:
    ```bash
    kubectl get pods --show-labels
    ```

### Resolution
1.  Fix the Kubernetes service port naming. It must follow the standard: `name: <protocol>[-<suffix>]` (e.g., `name: http-billing`).
2.  Align the VirtualService hostnames and DestinationRule subset labels with the actual pods.
3.  Redeploy the configurations.

### Prevention
Implement linting check tests (e.g., using `istioctl analyze`) inside your GitOps pipelines to catch mismatched label/host definitions before deployment.

---

## Scenario 4: Certificate Expiration
### Symptoms
Inter-service communication is down. Sidecar logs show errors like `transport: authentication handshake failed: tls: failed to verify certificate: x509: certificate has expired`.

### Root Cause
1.  `istiod` / Linkerd `identity` is degraded, overloaded, or down, preventing key renewals.
2.  The Secret Discovery Service (SDS) socket is blocked or unresponsive, preventing Envoy from loading updated key materials.

### Investigation
1.  Check control plane health:
    ```bash
    kubectl get pods -n istio-system
    ```
2.  Check the certificate age and expiration via `istioctl`:
    ```bash
    istioctl proxy-config secret <pod-name> -o json | jq '.dynamicActiveSecrets[].secret.tlsCertificate.certificateChain'
    ```
3.  Check `istiod` logs for signing errors:
    ```bash
    kubectl logs -n istio-system -l app=istiod --tail=200 | grep -E "CSR|sign|cert"
    ```

### Resolution
1.  Restart the control plane to force renewal loops:
    ```bash
    kubectl rollout restart deployment/istiod -n istio-system
    ```
2.  Restart affected sidecars to force them to reconnect to SDS:
    ```bash
    kubectl exec <pod-name> -c istio-proxy -- curl -X POST http://localhost:15000/quitquitquit
    ```

### Prevention
Configure Prometheus alerting for intermediate and root CA certificate expiration metrics (`citadel_server_root_cert_expiry_timestamp` or `linkerd_identity_cert_expiration_seconds`).

---

## Scenario 5: Control Plane Failures (OOM / Starvation)
### Symptoms
Config updates are slow to take effect (seconds or minutes). Deployments fail to start. Running `kubectl apply` for mesh CRDs times out. `istiod` restarts frequently.

### Root Cause
`istiod` has run out of memory (OOMKilled) because the size of the cluster endpoints, services, and namespace resources exceeds its allocated limits.

### Investigation
1.  Check for crash loops in the control plane:
    ```bash
    kubectl get pods -n istio-system -l app=istiod
    ```
2.  Inspect the termination reason:
    ```bash
    kubectl describe pod -n istio-system -l app=istiod | grep -E "Last State:|OOMKilled"
    ```
3.  Monitor the control plane memory and CPU consumption.

### Resolution
1.  Increase resource limits (CPU and Memory) for the `istiod` deployment.
2.  Deploy the `Sidecar` resource (in Istio) to limit the config push size.
3.  Scale the `istiod` replicas horizontally:
    ```bash
    kubectl scale deployment/istiod -n istio-system --replicas=3
    ```

### Prevention
Never deploy a service mesh in a large cluster with default resource configurations. Establish production baselines (e.g., minimum 2GiB memory per `istiod` replica for every 100 nodes).

---

## Scenario 6: Authorization Policy Issues (Unexpected HTTP 403)
### Symptoms
A client receives an `HTTP 403 Forbidden` response from a service. The client application logs show `RBAC: access denied`.

### Root Cause
1.  An `AuthorizationPolicy` is applied to the namespace or service but lacks rules matching the client's SPIFFE identity, path, method, or port.
2.  The client is calling the service over plaintext, preventing Envoy from verifying its identity, which causes identity-based policies to fail.

### Investigation
1.  Check Envoy RBAC logs. Enable debug logging:
    ```bash
    istioctl pc log <pod-name> --level rbac:debug
    ```
2.  Check the client's SPIFFE identity. Verify what identity Envoy presents:
    ```bash
    istioctl proxy-config secret <client-pod>
    ```
3.  List policies matching the target pod:
    ```bash
    kubectl get authorizationpolicies -A
    ```

### Resolution
1.  Adjust the policy to include the correct client SPIFFE URI principal:
    ```yaml
    spec:
      rules:
      - from:
        - source:
            principals: ["cluster.local/ns/<ns>/sa/<service-account>"]
    ```
2.  Enable debug logger to confirm which rule triggered the deny.

### Prevention
Run AuthorizationPolicies in `AUDIT` or `DRY-RUN` mode before setting them to `ALLOW`/`DENY`. Track metric `istio_rbac_allowed` vs `istio_rbac_denied`.

---

## Scenario 7: Service Communication Failures (iptables Loop)
### Symptoms
Pods cannot communicate with the internet or local services. CPU inside the pod spikes to 100% immediately on launch, and connection timeout errors occur.

### Root Cause
An routing redirect loop inside `iptables`. Typically caused by the application attempting to bind to the same port used by the proxy (e.g., `15001`, `15006`, `15008`, `15090`) or a loopback interface config error.

### Investigation
1.  Inspect application container configuration. Is it attempting to use Envoy ports?
2.  Check the `iptables` dump from the pod network namespace (requires container host access or `nsenter` debug pods):
    ```bash
    iptables -t nat -L -v
    ```
3.  Review proxy logs for circular call pathways.

### Resolution
1.  Change your application port to a standard non-conflicting port (e.g., `8080`, `3000`).
2.  If the loop is caused by traffic routing to external services, configure `global.outboundTrafficPolicy.mode` to `REGISTRY_ONLY` to block unregistered external calls.

### Prevention
Enforce policy linting rules that prevent application ports from matching reserved proxy control ports.

---

## Scenario 8: Latency Spikes
### Symptoms
The application experiences a sudden increase in response times (e.g., p99 latency increases by 50ms). Application logic remains unchanged.

### Root Cause
1.  Envoy's tracing, metrics, or logging integrations are overloaded.
2.  Deep tracing spans (e.g., sending telemetry sync calls to a degraded Jaeger endpoint).
3.  Envoy worker thread starvation due to heavy regex evaluation in L7 routing rules or WebAssembly plugins.

### Investigation
1.  Analyze request timing using proxy metrics:
    ```bash
    istioctl proxy-config bootstrap <pod-name>
    ```
2.  Check proxy CPU consumption. If CPU is high, check configuration size and active connections.
3.  Validate trace sampling rates. A rate of 100% causes high overhead.

### Resolution
1.  Reduce telemetry sampling rate (e.g., limit Jaeger trace sampling to 1% in production):
    ```yaml
    meshConfig:
      enableTracing: true
      defaultConfig:
        tracing:
          sampling: 1.0 # 1% sampling
    ```
2.  Simplify route tables. Avoid complex, recursive regular expressions in match statements.

### Prevention
Establish strict monitoring on sidecar CPU usage and scale CPU limits based on cluster traffic volume.

---

## Scenario 9: Mesh Upgrade Issues
### Symptoms
During a mesh version upgrade, some pods lose connection completely. Control plane shows version drift errors.

### Root Cause
Data plane proxies (Envoy) are too far behind the control plane (`istiod`) version. Istio supports a max of N-1 version compatibility. If you upgrade `istiod` by two major versions, older sidecars will fail to parse the updated xDS structure.

### Investigation
1.  Check data plane and control plane versions:
    ```bash
    istioctl version
    ```
2.  Look for Envoy config rejection logs:
    ```bash
    kubectl logs -n istio-system -l app=istiod | grep -E "rejected|xDS"
    ```

### Resolution
1.  Roll back `istiod` to the previous stable version.
2.  Execute canary upgrades using revisioned control planes (e.g., run `istiod-1-18` alongside `istiod-1-19` and shift namespaces progressively).
3.  Ensure all sidecars are updated before upgrading the control plane.

### Prevention
Always use **Canary Control Plane Upgrades** (revision-based tagging, e.g., `istioctl install --set revision=1-19-0`) in production. Never do in-place upgrades.

---

## Scenario 10: Multi-Cluster Communication Failures
### Symptoms
Pod A in Cluster A cannot resolve or reach Pod B in Cluster B. Logs show host resolution errors (e.g., `cannot resolve host-b.global`).

### Root Cause
1.  Cross-cluster DNS resolution is not configured (CoreDNS is not forwarding `.global` or cluster-specific domains).
2.  The East-West gateway IP is unreachable, or its LoadBalancer is offline.
3.  Firewall / Security Group rules block traffic between the cluster gateways on port `15008` (mTLS network tunnel).

### Investigation
1.  Test DNS resolution from a pod:
    ```bash
    kubectl exec <pod-name> -c <app-container> -- nslookup service-b.ns-b.svc.cluster.local
    ```
2.  Check gateway connectivity:
    ```bash
    kubectl get svc -n istio-system -l app=istio-eastwestgateway
    ```
3.  Review endpoint discovery status in `istiod`:
    ```bash
    istioctl proxy-config endpoints <pod-name> | grep -E "eastwest"
    ```

### Resolution
1.  Verify the East-West LoadBalancer has a valid external IP.
2.  Ensure firewall rules permit ingress on port `15008` (for Istio multi-network) or `443` (for Gateway-to-Gateway routing).
3.  Verify that your multi-cluster setup has synchronized core secrets containing API credentials for both API servers.

### Prevention
Implement automated end-to-end multi-cluster ping checks (e.g., run a cron job that checks connectivity between clusters every 5 minutes and alerts on failures).
