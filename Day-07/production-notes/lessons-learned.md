# 🧠 Lessons Learned: Operating Secure Configuration & Secrets at Scale

This document contains senior-level operational insights, architectural patterns, and hardening strategies compiled from managing enterprise-grade Kubernetes platforms.

---

## 1. Real-World Failure Modes & Post-Mortems

### Incident 1: The Infamous Log Leak
* **Symptom:** Core API keys compromised within minutes of deployment.
* **Root Cause:** A developer configured an environment variable `STRIPE_API_KEY` using `valueFrom`. The application startup sequence logged all system environment variables (`console.log(process.env)`) for debugging purposes. These logs were forwarded by the cluster daemonset to Elasticsearch, where developers and external contractors had read access.
* **Lessons Learned:** 
  1. Never log the environment block or print raw config inputs.
  2. Implement log scanning/scrubbing patterns (e.g., regex filters in Vector or FluentBit) to strip sensitive headers/tokens before they leave the node.
  3. Prefer Volume mounting. If variables must be injected as env, use a custom application wrapper that sanitizes or strips sensitive keys from local memory dumps.

### Incident 2: Config Drift & Out-of-Sync Secret Rotations
* **Symptom:** Databases rejected connections after an automated database password rotation.
* **Root Cause:** The database rotated the password, updating AWS Secrets Manager. The External Secrets Operator synced the updated password to the Kubernetes cluster. However, the application read the credentials on startup via environment variables. The application did not restart, continued using the stale password, and was eventually locked out when database connection limits were hit due to repeated authentication failures.
* **Lessons Learned:** 
  1. Dynamic configuration requires either file-system hot-reloads (polling or `inotify` watches) or automated pod rollouts.
  2. Implement controllers like **Reloader** (from Stakater) or include an automated rolling restart mechanism in your CD pipelines to bounce pods when their dependent Secret/ConfigMap digests change.

---

## 2. Managing Secret Sprawl
In large organizations with hundreds of microservices, managing duplicates of secrets across namespaces is a significant challenge.

### Anti-Patterns to Avoid
* **Wildcard RBAC Permissions:** Giving developers or CI/CD pipelines broad read access to all secrets in a namespace.
* **Copy-Pasting Secrets:** Copying secrets across namespace boundaries manually. This breaks tracing, invalidates audits, and complicates rotation.

### Production Patterns
* **Central Secret Controller:** Implement a central cluster-wide Secret manager like External Secrets Operator with `ClusterSecretStore` pointing to an enterprise vault.
* **ServiceAccount Mapping:** Restrict namespaces so they can only pull secrets belonging to their specific domain by mapping AWS IAM Roles (via IRSA / EKS Pod Identity) or GCP Workload Identity directly to the target namespace service accounts.

---

## 3. Operations & Compliance

### SOC2 / ISO 27001 Requirements
Audit readiness mandates strict controls around secrets:
* **No Plaintext in Git:** Any repository containing plaintext API keys or credentials instantly fails compliance audits.
* **Rotation Audits:** Proof that credentials (database passwords, API tokens) are rotated at regular intervals (typically 90 days or less).
* **Least Privilege Access:** Verification that cluster administrators do not have regular decrypt access to production secrets in `etcd` without logging.

### Encryption at Rest (KMS Plugin vs. Static Keys)
* **Default Encryption:** By default, data in `etcd` is unencrypted. This means if an attacker steals a backup of the `etcd` database, they have access to all secrets.
* **Local KMS Provider vs. Cloud KMS:** Do not use local static keys (`aescbc` in configuration) in production. If the configuration files are leaked, the keys are compromised.
* **KMS v2 in Kubernetes:** Implement Kubernetes KMS v2, which provides major performance benefits (key caching) and security improvements (envelope encryption with Cloud HSMs) over KMS v1.

---

## 4. HashiCorp Vault Operational Trade-Offs

While HashiCorp Vault is an industry standard, operating it at scale introduces unique challenges:

```
                  ┌──────────────────────┐
                  │ HashiCorp Vault HA   │
                  └──────────┬───────────┘
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
   [ Unseal Keys Management ]        [ Network Dependency ]
   - Auto-unseal via KMS/Cloud HSM   - Webhook timeout causes Pod block
   - Shamir Secret Sharing is manual - High latency impacts app start
```

* **The Unseal Bottleneck:** If the Vault pods restart, the vault enters a "sealed" state and cannot serve credentials. Ensure **Auto-Unseal** is configured using cloud provider KMS keys so that manual intervention is not required during node scaling events.
* **Network Latency & Timeout Loops:** When using the Vault Agent Injector mutating webhook, if the Vault cluster is under heavy load, pod scheduling will block or crash-loop due to webhook timeouts. Restrict webhook scopes, configure conservative timeouts, and keep local fallbacks where safe.

---

## 5. GitOps Patterns for Configuration & Secrets

In GitOps (with ArgoCD or Flux), the Git repository is the single source of truth. However, raw secrets must never exist in Git.

### Recommended Approaches
1. **ESO Pattern (Recommended):** Commit `ExternalSecret` manifests to Git. These manifests only reference the secret paths in the cloud secret manager. The operator reconciles them inside the cluster.
2. **Mozilla SOPS Pattern:** Commit encrypted secrets to Git. Encrypt the file using a cloud KMS key (e.g., AWS KMS ARN). ArgoCD runs a plugin that decrypts the secret manifests on the fly using cluster-assigned IAM roles before applying them.
3. **Bitnami SealedSecrets:** Developers run `kubeseal` to encrypt a secret using the cluster's public key. The resulting `SealedSecret` is safe to commit. The controller inside the cluster decrypts it using its private key. (Note: Rotating cluster keys can make older backups hard to recover if not managed carefully).
