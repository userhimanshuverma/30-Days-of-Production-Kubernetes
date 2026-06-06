# 🛡️ Day 15: Kubernetes Security Fundamentals
### 🏷️ PHASE 2 — RUNNING REAL APPLICATIONS

Welcome to Day 15. Today, we turn our attention to the absolute foundation of cluster operations: **Kubernetes Security**. 

In traditional static infrastructure, security was often treated as a perimeter firewall problem. In cloud-native environments, containers run side-by-side, Pods are dynamically scheduled across nodes, and microservices share the same physical kernel. Enforcing a zero-trust model requires securing every API transaction, workload identity, storage medium, and runtime configuration.

To design and operate a resilient, secure platform in production, engineers must understand how the API Server processes requests, how workload tokens are managed, and how container privileges are isolated. Today, we will deep dive into RBAC policies, Service Accounts, Pod Security Standards, Admission Controllers, and KMS secret encryption.

---

## 🗺️ Day 15 Directory Structure

Here is how today's learning resources are organized:
- [notes/security-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/notes/security-deep-dive.md) — Comprehensive technical reference detailing API groups, Service Account token projection, seccomp filters, and KMS envelope encryption.
- [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/) — 12 detailed sequence and workflow diagrams explaining RBAC, Service Accounts, Secrets, and Admission webhooks.
- [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/) — Production-ready YAML manifests for Role, RoleBinding, hardened Pod contexts, and encryption configuration.
- [labs/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/) — Step-by-step hands-on engineering labs.
  - [Lab 1: Configure RBAC & Service Accounts](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-1-rbac-and-service-accounts.md)
  - [Lab 2: Pod Security Standards & Security Contexts](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-2-pod-security-and-admission.md)
  - [Lab 3: Secret Protection, etcd Encryption & External Vaults](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-3-secret-protection-and-vault.md)
- [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/production-notes/lessons-learned.md) — Platform architecture insights on wildcard RBAC hazards, secrets mounting, image signature verification, and multi-tenant isolation.
- [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/troubleshooting/playbook.md) — Resolution playbooks for Forbidden API errors, webhook lockups, and security standard violations.
- [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/exercises/challenges.md) — Challenge scenarios to test your RBAC scope design and security context hardening.
- [resources/security-command-center.html](file:///d:/30_Days_of_Production_Kubernetes/Day-15/resources/security-command-center.html) — Futuristic, interactive, single-page HTML simulator dashboard.
- [resources/reference-links.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/resources/reference-links.md) — Curated bookmarks for official standards, hardening tools, and benchmarks.

---

## 1. Why Kubernetes Security Matters

In classical deployments, a server VM acts like a isolated physical house. If an intruder breaks in, they only compromise that specific house. 

Kubernetes is a **shared apartment building**. Workloads from different departments, teams, and trust levels run concurrently on the same compute nodes, sharing the underlying Linux kernel namespaces:

```
[ Compromised Pod ] ──(Kernel Exploit)──> [ Host Node Kernel ] ────┐
                                                                   ├──> [ Control Plane ]
[ Hardened Pod    ] ──(Dropped Caps)───> [ Host Node Kernel ] ────┘
```

If container processes are left unhardened, or if workloads possess excessive permissions to query the control plane, a single app compromise can result in the attacker gaining host node root access or hijacking database credentials across the entire cluster. Production Kubernetes requires a layered, defense-in-depth model built on the principle of least privilege.

---

## 2. RBAC (Role-Based Access Control) Deep Dive

Kubernetes authorizes all API Server interactions using **Role-Based Access Control (RBAC)** rules.

```
   Subject (User/Group/SA)
       │
       ├─► bound via RoleBinding ────► Role (Namespace scope, e.g., 'dev')
       │
       └─► bound via ClusterRoleBinding ─► ClusterRole (Cluster-wide scope)
```

### Key Concepts
* **API Groups, Resources & Verbs:** Every rule maps actions (verbs like `get`, `list`, `create`, `delete`) to API endpoints (resources like `pods`, `deployments`, `secrets`) inside logical groups (like `apps` or the core group `""`).
* **Roles vs. ClusterRoles:** A `Role` specifies permissions strictly confined inside a single namespace. A `ClusterRole` defines permissions spanning the entire cluster (like node queries) or namespaced resources across *all* namespaces.
* **Bindings:** A `RoleBinding` maps subjects to roles *within a namespace*. A `ClusterRoleBinding` grants the associated permissions *cluster-wide*.

---

## 3. Service Accounts & Workload Identity

While human users authenticate via external identity systems (OIDC), workloads running inside Pods authenticate using **Service Accounts**.

```
┌────────┐             TokenRequest             ┌────────────────┐
│        │ ───────────────────────────────────► │                │
│        │ ◄─────────────────────────────────── │                │
│        │             Signed JWT               │                │
│        │                                      │                │
│Kubelet │       Mount JWT (tmpfs memory)       │ Kube-APIServer │
│        │ ───────────────────────────────────► │                │
│        │                                      │                │
│        │             API call with Token      │                │
│        │ ◄─────────────────────────────────── │                │
└────────┘                                      └────────────────┘
```

### Projected Token Volumes
Modern Kubernetes clusters use **Bound Service Account Tokens**. When Kubelet starts a Pod, it uses the `TokenRequest` API to fetch a short-lived OIDC JSON Web Token (JWT) and mounts it inside the container using a memory-backed (`tmpfs`) volume.
* **Revocation:** The token is cryptographically bound to the specific Pod UID. If the Pod is deleted, the token is invalidated instantly.
* **Expiration:** Tokens default to a 1-hour lifetime, rotated atomically in memory by Kubelet.

---

## 4. Pod Security Standards & Security Contexts

Because containers share the host kernel, platforms must restrict what operations processes are allowed to execute.

### The Three Profiles (PSS)
1. **Privileged:** Unrestricted access. Allowed only for critical networking or logging daemonsets.
2. **Baseline:** Blocks known privilege escalations (restricts host paths, host namespaces, and host ports).
3. **Restricted:** Enforces rigorous hardening (requires non-root execution, read-only root filesystems, dropping all Linux capabilities, and enabling default seccomp profiles).

### Workload Hardening (YAML Context)
Compliance with the `Restricted` standard is configured via the `securityContext` keys in the manifest:
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
  containers:
    - name: app
      image: alpine
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
```

---

## 5. Admission Controllers & Policies

Admission Controllers are interceptors that review, mutate, or reject API requests after authentication and authorization, but before state is written to `etcd`.

```
[ Request ] ─► [ AuthN/AuthZ ] ─► [ Mutating ] ─► [ Schema ] ─► [ Validating ] ─► [ etcd ]
```

### Stages
1. **Mutating Webhooks:** Modifies the incoming object (e.g. injecting sidecars, appending environment values, or applying default resources).
2. **Schema Validation:** Verifies structural syntax.
3. **Validating Webhooks:** Performs security policy checks (e.g. validating image signatures or checking container contexts), rejecting non-compliant workloads.

---

## 6. Secret Protection & KMS Encryption

Kubernetes Secrets are merely **Base64-encoded strings** in etcd by default. Anyone with read permissions to etcd backups can decode them immediately.

```
+-------------------------------------------------------------------------+
|                  Write Secret Flow (KMS Envelope)                       |
|  Plaintext Secret ──► API Server ──► KMS (KEK Encrypts DEK) ──► etcd    |
+-------------------------------------------------------------------------+
```

### Production Patterns
* **Encryption at Rest:** Configuring `EncryptionConfiguration` using KMS providers to encrypt secrets before they are saved to disk.
* **External Secret Managers:** Using operators like the **External Secrets Operator (ESO)** to retrieve secrets from secure storage platforms (Vault, AWS Secrets Manager) at runtime.

---

## 7. Request Validation Journey (Flow Map)

Here is exactly how a request from a platform administrator or workload client is authenticated, validated, and stored inside the cluster database:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                              CLIENT HANDSHAKE                             │
│                         (kubectl apply -f pod.yaml)                       │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                          AUTHENTICATION (AuthN)                           │
│ 1. API Server checks request headers for Client Certs or JWT OIDC tokens. │
│ 2. Resolves identity: User "jane.dev" (Group: "system:authenticated").   │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                           AUTHORIZATION (AuthZ)                           │
│ 3. API Server checks RBAC rules. Checks if User "jane.dev" has "create"   │
│    permissions on resource "pods" in namespace "production".             │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                        MUTATING ADMISSION CONTROL                         │
│ 4. Mutating webhooks execute. Injects default sidecars (e.g. Istio) or   │
│    appends corporate logging environment flags.                           │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                             SCHEMA VALIDATION                             │
│ 5. API Server checks yaml syntax and keys against OpenAPI specification.  │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                       VALIDATING ADMISSION CONTROL                        │
│ 6. Validating webhooks execute. Verifies Pod Security Standards (PSS)     │
│    namespace labels. Rejects if pod is root or lacks drops capabilities.  │
└─────────────────────────────────────┬─────────────────────────────────────┘
                                      │
                                      ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                          etcd PERSISTENCE & KMS                           │
│ 7. If KMS encryption is ON, API Server encrypts plaintext to ciphertext.  │
│ 8. API Server writes state safely into etcd backend storage database.      │
│ 9. Returns HTTP 201 Created to the client interface.                      │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Real-world Production Security Scenarios

### Developer Namespace Boundaries
In multi-tenant engineering environments, developers belong to distinct teams. Using localized `Role` and `RoleBinding` definitions ensures developers can manage deployments inside their designated `dev` namespace, but cannot inspect configuration secrets or terminate service pods in the `production` namespace.

### Rootless Container Execution
In a hardened cluster, the built-in Pod Security Admission controller acts as a safety guard. If an unhardened third-party application is deployed without user configurations, the validation engine automatically blocks it, forcing engineers to configure user mappings and mount temporary folder cache directories on local memory disk instead.

---

## 🏁 Summary of Daily Tasks

To complete Day 15, proceed with the following steps:
1. **Explore Architecture Diagrams:** Study [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/) to visualize RBAC mappings, token lifecycles, and KMS decryption workflows.
2. **Read Deep-Dive Notes:** Review [notes/security-deep-dive.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/notes/security-deep-dive.md) to understand API groups, namespaces boundaries, and kernel-level runtime parameters.
3. **Interactive Simulation:** Open the [Security Command Center Simulator](file:///d:/30_Days_of_Production_Kubernetes/Day-15/resources/security-command-center.html) in your browser to experience authorization boundaries, policy enforcement rejections, and raw etcd encryption toggling.
4. **Execute Hands-on Labs:**
   * Run [Lab 1: Configure RBAC & Service Accounts](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-1-rbac-and-service-accounts.md) to test role policies.
   * Run [Lab 2: Pod Security Standards & Security Contexts](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-2-pod-security-and-admission.md) to enforce baseline and restricted standards.
   * Run [Lab 3: Secret Protection, etcd Encryption & External Vaults](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-3-secret-protection-and-vault.md) to configure etcd KMS keys and review External Secrets Operator sync models.
5. **Study Production Best Practices:** Read [production-notes/lessons-learned.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/production-notes/lessons-learned.md) to learn about wildcard binding risks, tmpfs secrets mounting, and multi-tenant quotas.
6. **Review Troubleshooting Playbook:** Walk through [troubleshooting/playbook.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/troubleshooting/playbook.md) to inspect and resolve 403 Forbidden checks, webhook timeouts, and standard validation errors.
7. **Complete Challenges:** Solve the RBAC scope, container hardening, and audit challenges in [exercises/challenges.md](file:///d:/30_Days_of_Production_Kubernetes/Day-15/exercises/challenges.md).
