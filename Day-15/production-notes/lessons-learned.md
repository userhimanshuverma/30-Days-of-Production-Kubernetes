# 🛡️ Production Security: Lessons Learned at Scale

Securing Kubernetes in production requires moving past basic tutorials. In large scale deployments, security issues arise from complex interactions between configurations, RBAC permissions, network layouts, and container vulnerabilities. 

This guide summarizes operational lessons learned from securing production Kubernetes clusters.

---

## 1. Overprivileged Service Accounts & RBAC Abuse

In production, workload identity is a high-priority target for attackers.

### The Problem: Wildcards and Escalation Path
Many Helm charts and developer setups default to `*` rules or give broad ClusterRoles for convenience.
- **Example Attack Path:** A front-end web server is compromised via an application vulnerability. If the web server Pod mounts a Service Account token with cluster admin or list-secrets permissions, the attacker extracts the token and uses it to take over the entire database or write files cluster-wide.

### Production Guardrails:
1. **Automount Disabling:** In your Pod definitions, always explicitly set:
   ```yaml
   spec:
     automountServiceAccountToken: false
   ```
   Only enable this on Pods that explicitly talk to the API (like operators or logging agents).
2. **Kubectl auth checks:** Run validation commands in CI/CD pipelines to audit what service accounts can do:
   ```bash
   kubectl auth can-i --as=system:serviceaccount:production:my-app-sa create pods
   ```
3. **Avoid `escalate` and `bind` Verbs:** In RBAC, users must not be allowed to bind Roles or escalate privileges unless they already possess those permissions. Minimize access to the `escalate` verb on `roles` and `clusterroles`.

---

## 2. Secrets Management & Decryption Risks

Storing configuration secrets in git repositories (GitOps) or in cleartext on disk is a primary source of data breaches.

### Key Risks
- **Base64 encoding exposure:** Developers frequently commit plain Base64-encoded Secrets to Git repositories, mistaking them for encrypted files.
- **Node-level memory access:** If a worker node is compromised, a root user can extract secrets from the active memory of Kubelet or by inspecting process environments.

### Production Hardening:
1. **Never use base64 secrets in Git:** Use tools like **Sealed Secrets (Bitnami)**, **SOPS (Mozilla)**, or **External Secrets Operator** integrated with AWS/GCP KMS.
2. **Mount Secrets as Volumes:** Avoid injecting secrets as environment variables (`envFrom` or `valueFrom`). Environment variables are often printed in application crash logs, visible via `kubectl describe pod`, or accessible via `/proc/<pid>/environ`.
   * *Instead, mount them as files:* These files are mounted on a temporary memory filesystem (`tmpfs`). They never touch host storage disks and vanish when the container process terminates.

---

## 3. Container Vulnerabilities & Supply Chain Security

Compromises often start inside the container, not the cluster.

### Hardening Container Boundaries
- **Use Minimal Images:** Avoid standard Ubuntu or Debian images that bundle compilers, packages, curl, or shell environments. Use **Distroless** or minimal **Alpine** images.
- **Rootless execution:** Enforce that containers run with a non-root UID. The container runtime should map container UIDs to unprivileged UIDs on the host system.
- **Image Signing & Verification:** Use tools like **Cosign** (Sigstore) in your CI/CD. Apply admission controller rules (e.g., Kyverno) that reject images if their cryptographic signatures do not match your keys.

---

## 4. Multi-Tenant Hardening

If your cluster hosts multiple applications or different teams, you must enforce isolation boundaries.

### Key Pillars of Multi-Tenancy:
1. **Network Isolation:** Create a default-deny ingress/egress NetworkPolicy for every namespace. Explicitly whitelist connections between namespaces.
2. **Resource Quotas:** Prevent a single compromised or runaway namespace from causing a Denial of Service (DoS) across other tenants:
   ```yaml
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: compute-quota
     namespace: team-alpha
   spec:
     hard:
       requests.cpu: "4"
       requests.memory: 8Gi
       limits.cpu: "8"
       limits.memory: 16Gi
   ```
3. **Node Selector & Taints:** Isolate critical system workloads (like payment processing or authentication modules) onto dedicated, hardened nodes using node taints and tolerations.

---

## 5. Security Auditing & Compliance

Security is not complete without audit verification.

### Config Audit
Enable the **API Server Audit Log**. Audit policies specify what events are recorded:
- Write metadata only for low-risk actions.
- Write request and response payloads for high-risk operations (e.g., updates to Secrets, RoleBindings, or ClusterRoleBindings).
- Direct audit logs to an external security monitoring tool (SIEM) using a log aggregator (like Fluentbit or Vector) immediately.

### Static Verification (Policy as Code)
Integrate static scanning into git branches and CI/CD pipelines before deployment using:
- **Trivy / Kubesec:** Checks YAML manifests for unhardened parameters (e.g. running as root, missing resource limits).
- **Kube-bench:** Runs CIS Kubernetes Benchmark tests on nodes and control plane services to detect compliance failures.
