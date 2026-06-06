# 🚨 Day 15 Security Troubleshooting Playbook

This playbook provides actionable diagnostic guides for common Kubernetes security errors, permissions blocks, and policy violations.

---

## Scenario 1: HTTP 403 Forbidden (RBAC Errors)

### Symptoms
When a client (user or pod application) executes a command, they receive:
```
Error from server (Forbidden): pods is forbidden: User "jane" cannot list resource "pods" in API group "" in the namespace "dev"
```

### Root Cause
The user or service account making the call does not have a RoleBinding or ClusterRoleBinding linking them to a Role containing the requested resource/verb combination.

### Investigation
1. **Verify target identity:** Identify exactly who is calling. Is it a User, Group, or ServiceAccount?
2. **Perform authorization check (`kubectl auth can-i`):**
   ```bash
   # Check if user jane can perform the action
   kubectl auth can-i list pods --as=jane --namespace=dev
   
   # Check for a Service Account inside a namespace
   kubectl auth can-i list pods --as=system:serviceaccount:dev:dev-ci-runner --namespace=dev
   ```
3. **List active bindings:**
   ```bash
   kubectl get rolebindings,clusterrolebindings -n dev -o wide
   ```
4. **Inspect Role definition:** Find the role referenced by the binding and check if the API group, resource, or verb is missing:
   ```bash
   kubectl get role <role-name> -n dev -o yaml
   ```

### Resolution
Modify or create a `Role` (or `ClusterRole`) listing the missing resources and verbs, and bind it to the subject:
```yaml
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
```

### Prevention
Integrate `kubectl auth can-i` validation tests in CI/CD pipelines to verify deployment credentials before applying them.

---

## Scenario 2: Service Account Token Issues (Expired/Not Mounted)

### Symptoms
An application container crashes on start, or prints API client logs showing:
```
Open /var/run/secrets/kubernetes.io/serviceaccount/token: no such file or directory
```
Or API requests return `401 Unauthorized`.

### Root Cause
1. The ServiceAccount has `automountServiceAccountToken: false` set on the SA or Pod spec, preventing the mount.
2. In older clusters, the Service Account Token secret was deleted. In newer clusters, the projected token volume volume mount was overridden in the Pod spec.

### Investigation
1. **Check automount settings:** Inspect the ServiceAccount and Pod spec configuration:
   ```bash
   kubectl get sa <sa-name> -n dev -o yaml | grep automount
   kubectl get pod <pod-name> -n dev -o yaml | grep automount
   ```
2. **Verify mount directory inside container:**
   ```bash
   kubectl exec <pod-name> -n dev -- ls -l /var/run/secrets/kubernetes.io/serviceaccount/
   ```

### Resolution
1. Set `automountServiceAccountToken: true` in the Pod spec or ServiceAccount if the workload needs API server access.
2. If using custom mounts, verify the projected token volume is declared correctly:
   ```yaml
   spec:
     volumes:
       - name: token-vol
         projected:
           sources:
             - serviceAccountToken:
                 audience: api
                 expirationSeconds: 3600
                 path: token
   ```

### Prevention
Include checking templates for correct token mounts in GitOps compliance guidelines.

---

## Scenario 3: Pod Security Standards Violation (Baseline/Restricted Rejection)

### Symptoms
Deployments fail to scale, replica sets remain empty. Running `kubectl describe deployment` or `kubectl get events -n dev` shows:
```
Warning  FailedCreate  1s  replicaset-controller  Error creating: pods "secure-web-" is forbidden: violates PodSecurity "restricted:latest": non-root user (container "web" must run as non-root), read-only root filesystem (container "web" must use a read-only root filesystem)
```

### Root Cause
The target namespace enforces a Pod Security Standard (Baseline or Restricted) that the incoming Pod specification violates (e.g. running as root, or attempting to write directly to the container root filesystem).

### Investigation
1. **Check Namespace Labels:** Find the Pod Security Admission level enforced on the namespace:
   ```bash
   kubectl get ns <namespace-name> --show-labels
   ```
2. **Inspect the Rejection Details:** Read the event list for the specific validation messages:
   ```bash
   kubectl get events -n <namespace-name> --field-selector reason=FailedCreate
   ```
3. **Analyze the Pod Spec:** Compare the Pod spec container settings to the standard rule requirements (e.g. check for `privileged: true`, or missing `securityContext` keys).

### Resolution
Modify the Pod spec to apply the necessary security settings. For the `restricted` standard:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  seccompProfile:
    type: RuntimeDefault
containers:
  - name: web
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
```

### Prevention
Configure local IDE linting (like `kubeval` or `kube-score`) and run lint validations in pre-commit hooks to block unhardened manifests before commit.

---

## Scenario 4: Webhook Admission Failures (Fail-Closed Lockups)

### Symptoms
Any request to deploy resources (or even write namespace config) times out or yields:
```
Error from server (InternalError): Internal error occurred: failed calling webhook "validate.kyverno.svc": Post "https://kyverno-svc.kyverno.svc:443/validate": dial tcp 10.96.24.5:443: connect: connection refused
```
The entire cluster control plane may feel locked.

### Root Cause
A Mutating or Validating Webhook Configuration (like Kyverno or OPA Gatekeeper) is defined as `failurePolicy: Fail` (fail-closed), and the webhook pod is crashlooping, network-isolated, or deleted.

### Investigation
1. **List webhook configurations:**
   ```bash
   kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations
   ```
2. **Check policy settings:** Find the webhook configuration causing issues:
   ```bash
   kubectl get validatingwebhookconfiguration <config-name> -o yaml
   ```
   Check for `failurePolicy: Fail` and the endpoint service details.
3. **Inspect the webhook service health:** Check if the webhook controller pods are running:
   ```bash
   kubectl get pods -n kyverno # or the respective namespace
   ```

### Resolution
1. **Emergency recovery:** If the cluster is completely blocked and you must recover immediately, patch the webhook configuration to `Ignore` (fail-open) or delete it:
   ```bash
   # Temporarily bypass the webhook by changing failurePolicy
   kubectl patch validatingwebhookconfiguration <config-name> --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value": "Ignore"}]'
   ```
2. Diagnose and fix the underlying issue in the policy engine controller (e.g. check logs, renew expired web certificates, scale up replicas).

### Prevention
1. Set up high-availability (HA) setups (3 replicas) for all admission webhook controllers.
2. Use resource exemptions (like excluding system namespaces or specific administrator roles) so webhooks do not lock up recovery processes.
