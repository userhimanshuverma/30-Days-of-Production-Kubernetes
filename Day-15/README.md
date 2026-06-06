# 🛡️ Day 15: Kubernetes Security Fundamentals
### 🏷️ PHASE 2 — RUNNING REAL APPLICATIONS

> **TL;DR:** Learn the five pillars of Kubernetes cluster security: Role-Based Access Control (RBAC), Service Accounts, Pod Security Standards (PSS), Admission Control, and Secret Encryption at Rest.

---

## 🎯 Learning Objectives
By the end of today, you will be able to:
1. Explain the multi-layered **Kubernetes Security Model** and its threat boundaries.
2. Design least-privilege **RBAC Policies** (Roles, ClusterRoles, Bindings) without using risky wildcards.
3. Harden **Service Accounts** for workload authentication using projected tokens.
4. Enforce **Pod Security Standards (PSS)** at the Namespace level to block privileged containers.
5. Understand the request lifecycle inside **Admission Controllers** (Mutating vs. Validating webhooks).
6. Implement safe **Secret Management** (etcd encryption at rest and Vault integrations).
7. Diagnose and debug security, authorization, and admission failures.

---

## 📂 Day 15 Repository Structure
This directory is structured as an enterprise-grade Kubernetes security workspace:
* [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/) — Scoped roles, secure Pod security contexts, and etcd encryption configurations.
* [diagrams/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/) — Detailed sequence and workflow diagrams explaining RBAC, Service Accounts, Secrets, and Admission webhooks.
* [notes/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/notes/) — Theoretical deep dives on API groups, Kubernetes authentication, and kernel primitives.
* [production-notes/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/production-notes/) — Operational warnings: default service accounts, GitOps secret leaks, and multi-tenant security.
* [labs/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/) — Hands-on step-by-step laboratories to test permissions, simulate violations, and configure KMS.
* [troubleshooting/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/troubleshooting/) — Playbook containing root cause analyses and diagnostics for Forbidden errors, webhook locks, and PSS blockages.
* [exercises/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/exercises/) — Independent challenges to audit overprivileged systems and harden YAML manifests.
* [resources/](file:///d:/30_Days_of_Production_Kubernetes/Day-15/resources/) — Interactive HTML Simulator dashboard and external reference links.

---

## 1. Why Kubernetes Security Matters

### 💡 The Analogy: The Apartment Building
Think of a standard server virtual machine (VM) as a single-family house. If you break in through a window, you control the whole house. 
A **Kubernetes cluster is an apartment building**. Multiple tenants (workloads) share common spaces (the Linux Kernel, networks, CPU/RAM, and storage). If you leave the front lobby unlocked (no RBAC) or allow tenants to remodel the building structure (privileged containers), a compromise in one apartment can lead to the collapse of the entire building.

```
       [ Kubernetes Security Defense-in-Depth Model ]
       
    ┌───────────────────────────────────────────────┐
    │  Cloud/Host Security (OS, IAM, VPC Firewalls) │
    │  ┌─────────────────────────────────────────┐  │
    │  │ Cluster Gatekeepers (API, AuthN, RBAC)  │  │
    │  │ ┌─────────────────────────────────────┐ │  │
    │  │ │ Container Hardening (Non-root, PSS)  │ │  │
    │  │ │ ┌─────────────────────────────────┐ │ │  │
    │  │ │ │ Application Code (SAST, Secrets)│ │ │  │
    │  │ │ └─────────────────────────────────┘ │ │  │
    │  │ └─────────────────────────────────────┘ │  │
    │  └─────────────────────────────────────────┘  │
    └───────────────────────────────────────────────┘
```
See the complete [Production Security Layers Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/production-security-layers.md) for a breakdown of these boundaries.

---

## 2. RBAC Deep Dive (Role-Based Access Control)

RBAC defines who (Subject) can perform what (Verb) on which object (Resource) inside the cluster.

### Roles vs. ClusterRoles
* **`Role`**: Namespaced. Grants access to resources inside a specific namespace (e.g. `dev`).
* **`ClusterRole`**: Cluster-scoped. Grants access to cluster-wide resources (like Nodes, Namespaced API resource names across *all* namespaces, or PersistentVolumes).

### RoleBindings vs. ClusterRoleBindings
* **`RoleBinding`**: Links a subject to a Role/ClusterRole inside a *specific namespace*.
* **`ClusterRoleBinding`**: Links a subject to a ClusterRole *cluster-wide*.

```
   Subject (User/Group/SA)
       │
       ├─► bound via RoleBinding ────► Role (Namespaced Scope)
       │
       └─► bound via ClusterRoleBinding ─► ClusterRole (Cluster-wide Scope)
```

> [!IMPORTANT]
> **Production Best Practice:** Never use wildcards (`*`) for verbs or resources in production manifests. Limit permissions to the exact verbs needed (e.g., `["get", "list", "watch"]`).
> Review our [Least Privilege Model Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/least-privilege-model.md) for a visual comparison of safe vs. unsafe RBAC.

Refer to the [RBAC Architecture Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/rbac-architecture.md) and learn to apply these in [Lab 1: Configure RBAC & Service Accounts](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-1-rbac-and-service-accounts.md).

---

## 3. Service Accounts (Workload Identity)

Kubernetes uses **Service Accounts** to authorize workloads running inside pods to make requests to the API Server.

### The Authentication Flow
When a Pod starts, the Kubelet requests an OIDC-compliant JSON Web Token (JWT) from the API Server and mounts it as a projected volume into the container at `/var/run/secrets/kubernetes.io/serviceaccount/token`. 

```
┌───────┐             TokenRequest              ┌────────────────┐
│       │ ────────────────────────────────────► │                │
│       │ ◄──────────────────────────────────── │                │
│       │             Signed JWT                │                │
│       │                                       │                │
│Kubelet│       Mount JWT (tmpfs memory)        │ Kube-APIServer │
│       │ ────────────────────────────────────► │                │
│       │                                       │                │
│       │             API call with Token       │                │
│       │ ◄──────────────────────────────────── │                │
└───────┘                                       └────────────────┘
```
See the [Service Account Token Lifecycle Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/service-account-lifecycle.md) and [Client Authentication Flow Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/authentication-flow.md) for details.

### Security Hardening Service Accounts
1. **Disable Auto-mounting:** If your app doesn't call the Kubernetes API, prevent token access:
   ```yaml
   automountServiceAccountToken: false
   ```
2. **Disable default Service Account privileges:** The default Service Account in a namespace should have zero RBAC permissions bound.

---

## 4. Pod Security Standards & Security Contexts

Because containers share the host kernel, an unhardened container process can compromise the underlying node.

### Pod Security Standards (PSS)
Kubernetes defines three profiles to simplify namespace-level workload protection:
1. **Privileged:** No restrictions. Only for system daemons (like CNI plugins).
2. **Baseline:** Prevents known privilege escalations (restricts host paths, host namespaces, and volume types).
3. **Restricted:** Enforces strict hardening (requires running as non-root, read-only root filesystems, dropping all Linux capabilities, and enabling default seccomp profiles).

### Applying Security Contexts (YAML Example)
To comply with the **Restricted** standard, we specify settings on both the Pod and Container level:
```yaml
spec:
  securityContext: # Pod Level
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: alpine
      securityContext: # Container Level
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
```
See how this translates to kernel-level sandboxing in the [Pod Security Context Architecture Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/pod-security-architecture.md) and practice applying it in [Lab 2: Pod Security Standards & Security Contexts](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-2-pod-security-and-admission.md).

---

## 5. Admission Controllers

Admission Controllers act as gatekeepers that intercept API requests *after* authentication and authorization, but *before* write operations to etcd.

```
          [ Request ] ─► [ Authentication & Authorization ]
                                      │
                                      ▼
                        [ Mutating Admission Webhooks ]
                                      │
                                      ▼
                          [ Schema Validation ]
                                      │
                                      ▼
                       [ Validating Admission Webhooks ]
                                      │
                                      ▼
                              [ Write to etcd ]
```

### Types of Webhooks
* **Mutating Webhooks:** Modifies the request (e.g. injecting log forwarding sidecars or default environment keys).
* **Validating Webhooks:** Inspects the finalized configuration and rejects requests that violate corporate policies (e.g. blocking images containing severe CVEs, or ensuring image signatures match).

For a step-by-step look, view the [Admission Controller Workflow Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/admission-controller-workflow.md) and the [Request Validation Pipeline Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/request-validation-pipeline.md).

---

## 6. Secret Protection & External Store Integrations

Kubernetes Secrets are stored in the etcd database using **Base64 serialization**. Base64 is not encryption; it is simply an encoding scheme.

### Hardening Secrets in Production
1. **Enable Encryption at Rest:** Configure the API Server to encrypt secrets before writing them to the etcd disk using a Key Management Service (KMS) provider.
2. **Use External Secret Vaults:** Avoid keeping secret files inside Git. Implement the **External Secrets Operator (ESO)** to sync secrets from AWS Secrets Manager, GCP Secret Manager, or HashiCorp Vault directly into the cluster at runtime.

Refer to the [Secret Storage and Access Flow Diagram](file:///d:/30_Days_of_Production_Kubernetes/Day-15/diagrams/secret-access-flow.md) and walk through configuration in [Lab 3: Secret Protection, etcd Encryption & External Vaults](file:///d:/30_Days_of_Production_Kubernetes/Day-15/labs/lab-3-secret-protection-and-vault.md).

---

## 🚀 Interactive Simulation: Security Command Center
We have generated a fully interactive HTML simulator that models the Kubernetes request pipeline.
You can run it to visually trace:
- How **RBAC** decisions allow or deny API actions.
- How **Admission Controller policies** dynamically reject insecure Pod configurations.
- How **etcd Encryption at Rest** secures database credentials.

👉 **Launch Simulator:** [security-command-center.html](file:///d:/30_Days_of_Production_Kubernetes/Day-15/resources/security-command-center.html) *(Open this file in your local web browser to start the simulation).*

---

## 🚨 Ready to Troubleshoot?
If you encounter permission errors, admission rejections, or volume mount lockups, open the [Day 15 Troubleshooting Playbook](file:///d:/30_Days_of_Production_Kubernetes/Day-15/troubleshooting/playbook.md) for clear diagnostics and solutions.
