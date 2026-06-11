# 📓 GitOps at Scale: Multi-Cluster, Secrets, and Governance
### 🏷️ SENIOR ENGINEERING PLAYBOOK

Operating GitOps for a few applications on a single cluster is simple. Scaling GitOps to manage 500+ microservices, dozens of developer teams, and hundreds of Kubernetes clusters across multiple clouds introduces structural, security, and operational challenges.

This note documents the lessons learned running GitOps platforms in production at enterprise scale.

---

## 📂 1. Repository Structure Strategies

How you organize your Git repositories is the single most important design decision in GitOps. There are three primary patterns:

### Pattern A: Mono-Repo (Single Repo for Everything)
All application manifests and cluster definitions live in a single repository.
* **Pros:** Complete visibility of the entire organization's state. Easy to apply global changes (e.g., updating an API version of a CRD everywhere).
* **Cons:** Git performance degrades with size (cloning gigabytes of text). CI/CD trigger loops are complex (avoiding triggering a rebuild of App A when App B changes). Access control is difficult (Git providers don't natively restrict subdirectory access within a single repo easily).

### Pattern B: Multi-Repo (Repo-per-App + Cluster Config Repo)
Each application team has their own repository containing application code and a `manifests/` folder. A central "Cluster Config Repo" defines cluster structures and references the individual app repos.
* **Pros:** Teams operate independently. High developer velocity. Narrow blast radius.
* **Cons:** Hard to enforce global compliance standards. Difficult to track the global state of the enterprise from a single point.

### Pattern C: Config-Only Repo (Recommended)
Separate the application source code from the infrastructure definition.
* **Application Repo:** Contains code, unit tests, Dockerfile, and CI workflows.
* **Config Repo:** Contains ONLY Kubernetes manifests (no code), environment configurations (dev, staging, prod) styled as Kustomize overlays.
* **Pros:** Strong security boundary. Developers don't need write access to the Config Repo to commit code. Only the CI bot has write access to the Config Repo to bump image tags. Keeps Git history clean of code changes.

---

## 🔑 2. Secrets Management in GitOps

Since Git is the source of truth, **you must never store plaintext secrets (like passwords, API keys, or certificates) in Git.** Doing so is a severe compliance and security violation.

Here are the three production-grade methods to handle secrets in GitOps:

### Method 1: External Secrets Operator (ESO) - Recommended
Instead of storing secrets in Git, you store them in an external Vault (HashiCorp Vault, AWS Secrets Manager, Google Secret Manager). The External Secrets Operator runs in your cluster and synchronizes secrets from the Vault provider into native Kubernetes `Secret` resources.

```
[ Git Repo ] ──> [ ExternalSecret Manifest ] ──> [ ESO Operator ]
                                                         ▲
                                                 (Fetches Secret)
                                                         │
                                                 [ Secret Manager ]
```
* **Pros:** Highly secure. Integrates with cloud IAM. Secrets are rotated automatically.
* **Cons:** Requires running another operator in the cluster.

### Method 2: Sealed Secrets (Bitnami)
You encrypt your Kubernetes secret locally using a public key provided by the Sealed Secrets controller running in your cluster. Once encrypted, the secret becomes a `SealedSecret` custom resource, which can be safely committed to Git. Only the controller running in your cluster can decrypt it using its private key.
* **Pros:** Simple setup, no external dependencies, git-native encryption.
* **Cons:** Decryption depends on the controller's private key. If you lose the controller's namespace or backing store without backing up the key, you cannot restore the secrets.

### Method 3: Mozilla SOPS
SOPS allows you to encrypt specific values within a YAML manifest using cloud KMS keys (AWS KMS, GCP KMS, Azure Key Vault) or PGP. Both Flux and ArgoCD have plugins to decrypt SOPS-encrypted files during reconciliation.
* **Pros:** File remains a valid YAML file, encryption key management is delegated to cloud providers.
* **Cons:** Requires installing decryption plugins on the GitOps repo server.

---

## 🌐 3. Multi-Cluster GitOps Management

Managing multi-cluster environments manually results in copy-paste configurations. Production GitOps uses automated templating engines to generate cluster-specific applications.

### ArgoCD ApplicationSets
Instead of creating 50 separate `Application` manifests for 50 clusters, you write a single `ApplicationSet` that generates applications based on list metadata or dynamic configurations:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: dynamic-deployer
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: production
  template:
    metadata:
      name: '{{name}}-billing-service'
    spec:
      project: default
      source:
        repoURL: 'https://github.com/org/billing-service.git'
        targetRevision: HEAD
        path: deployments/prod
      destination:
        server: '{{server}}' # <--- Injects target cluster API server
        namespace: billing
```

### Flux Multi-Cluster Bootstrap
With Flux, you can manage multi-cluster structures by pointing all clusters to a single Git repository containing a directory layout structured by cluster:

```
clusters/
├── dev-cluster/
│   ├── flux-system/
│   └── infrastructure.yaml (points to apps/base + dev patch)
├── staging-cluster/
│   ├── flux-system/
│   └── infrastructure.yaml (points to apps/base + staging patch)
└── prod-cluster/
    ├── flux-system/
    └── infrastructure.yaml (points to apps/base + prod patch)
```
Each cluster is bootstrapped against its specific directory, preventing cross-cluster contamination.

---

## 🛡️ 4. Governance and Auditing

GitOps shifts the audit boundary from Kubernetes API logs to Git logs.

### Compliance Best Practices:
1. **Enforce Branch Protections:** Block direct commits to the `main` branch. Require at least two SRE approvals and successful validation checks (e.g., YAML linting, security scanning via Trivy) before merging.
2. **Restrict Controller Permissions:** Don't run the GitOps operator with cluster-admin keys if you have multiple development teams. Map the controller to namespaces using specific ServiceAccounts and namespace-bound `RoleBindings` rather than `ClusterRoleBindings`.
3. **Write Policy as Code:** Run Kyverno or OPA Gatekeeper in the cluster. If a developer attempts to commit an insecure manifest to Git (e.g., requesting a container to run as root), the policy engine inside the cluster will block the GitOps agent from applying it, marking the application state as `Degraded`.
