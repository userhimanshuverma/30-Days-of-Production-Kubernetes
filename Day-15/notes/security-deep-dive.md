# 📖 Day 15: Kubernetes Security Deep Dive

In production Kubernetes, security is not an afterthought or an optional layer. Because Kubernetes orchestrates shared resources across nodes, compute, and data layers, a single misconfiguration can open the door to complete cluster compromise. 

This guide covers the core security pillars that protect users, workloads, secrets, and control plane resources.

---

## 1. Role-Based Access Control (RBAC)

RBAC controls access to the Kubernetes API Server. Every request to the API server is authenticated, and then authorized using RBAC.

### API Groups, Resources, and Verbs

The Kubernetes API is organized hierarchically. An RBAC rule consists of three core components:
1. **`apiGroups`**: Logical groupings of API resources.
   - Core resources (like Pods, Services, ConfigMaps) belong to the empty API group `""`.
   - Extensions and controllers belong to named groups like `"apps"` (Deployments, StatefulSets), `"batch"` (Jobs, CronJobs), or `"networking.k8s.io"` (NetworkPolicies, Ingresses).
2. **`resources`**: The objects to act upon, e.g., `["pods"]`, `["deployments"]`, `["secrets"]`. You can also target subresources (like `["pods/log"]` or `["pods/exec"]`).
3. **`verbs`**: The actions allowed on those resources, e.g., `["get", "list", "watch", "create", "update", "patch", "delete"]`.

### Roles vs. ClusterRoles

| Dimension | Role | ClusterRole |
|---|---|---|
| **Scope** | Restricted to a single Namespace. | Cluster-wide (applies to all namespaces). |
| **Use Case** | Granting permissions to app deployments or developers in a specific namespace (e.g. `dev`). | Granting permissions to cluster admins, security auditors, or targeting cluster-scoped resources (e.g., Nodes, PVs). |
| **API Groups** | Can only grant access to namespaced resources. | Can grant access to namespaced resources AND cluster-scoped resources (like Nodes, Namespaces, PVs). |

### RoleBindings vs. ClusterRoleBindings

* **`RoleBinding`**: Connects a `Role` (or a `ClusterRole`) to a set of subjects (Users, Groups, Service Accounts) **within a specific namespace**.
* **`ClusterRoleBinding`**: Connects a `ClusterRole` to subjects **cluster-wide**, granting those permissions across all namespaces and cluster-scoped APIs.

> [!WARNING]
> Binding a `ClusterRole` containing cluster-wide write capabilities (like cluster-admin permissions) via a `ClusterRoleBinding` is equivalent to granting full root access to the cluster. Always prefer narrow `RoleBindings` unless cluster-wide operations are unavoidable.

---

## 2. Service Accounts (Workload Identity)

While human users authenticate via external systems (like OIDC or Active Directory), **pods and workloads authenticate using Service Accounts**.

### projected Token Volume (Bound Service Account Tokens)

Historically, Kubernetes mounted a static, long-lived Service Account token from a Secret into `/var/run/secrets/kubernetes.io/serviceaccount/token`. If stolen, this token was valid forever.

Modern Kubernetes clusters (v1.22+) use **Bound Service Account Tokens** via `projected` volumes:
* **Time-Bound:** Tokens expire (typically after 1 hour). The Kubelet automatically requests a new one and rotates it in the Pod's memory space.
* **Audience-Bound:** Tokens contain an `aud` claim matching the API server.
* **Pod-Bound:** The token is tied to the specific Pod UID. If the Pod is terminated, the token is instantly revoked by the API Server.

### Hardening Service Accounts

By default, every namespace contains a service account named `default`. If you do not specify a service account, pods automatically mount this `default` token.

**Hardening Rules:**
1. **Disable automounting:** If your application does not need to communicate with the Kubernetes API Server, disable token mounting:
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: my-app-sa
   automountServiceAccountToken: false
   ```
2. **Create custom SAs:** Never bind RBAC permissions to the `default` service account. Create distinct Service Accounts for each application.

---

## 3. Pod Security Standards (PSS) & Pod Security Admission (PSA)

Containers share the host kernel. If a container runs with administrative privileges, it can compromise the host node. Kubernetes provides **Pod Security Standards** to define hardening boundaries.

### The Three Security Standards

1. **Privileged (Unrestricted):**
   - Allows known privilege escalations.
   - Used only for system-level daemonsets (e.g., CNI plugins, kube-proxy, log forwarders).
2. **Baseline (Default):**
   - Prevents known privilege escalations.
   - Blocks pods from mounting host paths, running host network/PID namespaces, or sharing the host IPC namespace.
3. **Restricted (Highly Hardened):**
   - Enforces best-practice container hardening rules.
   - Requires processes to run as a non-root user (no UID 0).
   - Requires a read-only root filesystem (`readOnlyRootFilesystem: true`).
   - Requires dropping all Linux capabilities and restricting seccomp profiles to `RuntimeDefault`.

### Pod Security Admission (PSA)

Kubernetes enforces these standards at the namespace level using labels:
```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
```
* **`enforce`**: Rejects any pod creation requests that violate the standard.
* **`warn`**: Generates a warning message visible to the user during creation but allows deployment.
* **`audit`**: Adds an entry to the audit logs when a violating pod is created.

---

## 4. Admission Controllers

Admission Controllers are interceptors that inspect, mutate, or reject API requests before objects are saved to `etcd`.

```
[Request] ──> [Authenticate & Authorize] ──> [Mutating Webhooks] ──> [Schema Validation] ──> [Validating Webhooks] ──> [etcd]
```

### Mutating vs. Validating Webhooks

1. **Mutating Webhooks:**
   - Run first.
   - Can modify the incoming manifest (e.g., injecting an Envoy sidecar container, adding resource limits, appending environment variables).
2. **Validating Webhooks:**
   - Run after schema validation.
   - Can only accept or reject requests (e.g., verifying if the container image comes from a trusted corporate registry, or checking if the image has been signed).

### Third-Party Policy Engines

While built-in PSA works well for basic security, enterprise platforms use advanced policy engines:
* **OPA Gatekeeper:** Uses Rego, a declarative query language, to write custom policies.
* **Kyverno:** A Kubernetes-native policy engine that uses standard YAML declaration to write policies, make mutations, and generate compliance reports.

---

## 5. Secret Protection

By default, Kubernetes Secrets are stored in `etcd` as base64-encoded strings. **Base64 is NOT encryption!** Anyone with access to etcd or read-permissions on secrets can read the sensitive data.

### Encryption at Rest (KMS Plugin)

To protect secrets, the cluster control plane must be configured with an `EncryptionConfiguration` mapping a KMS provider:
* **Key Management Service (KMS):** The API Server delegates encryption/decryption of secrets to cloud-native KMS (AWS KMS, GCP KMS, Azure Key Vault) or HashiCorp Vault.
* **Envelope Encryption:** Secrets are encrypted using a local Data Encryption Key (DEK). The DEK is encrypted using a Key Encryption Key (KEK) managed in the external KMS.

### Secret Stores CSI Driver & External Secrets Operator (ESO)

Instead of storing secrets in etcd at all, modern GitOps systems integrate with external secret vaulting systems:
1. **Secret Store CSI Driver:** Mounts secrets from external systems (e.g., AWS Secrets Manager, Vault) directly as files inside container pods, using a CSI volume. Secrets never get persisted in etcd.
2. **External Secrets Operator (ESO):** An operator that queries the external vault system and automatically synchronizes the values into native Kubernetes `Secret` resources in the namespace.
