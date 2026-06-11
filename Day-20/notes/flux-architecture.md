# 📔 Flux v2 Architecture: The GitOps Toolkit

Flux v2 is a modular, Kubernetes-native set of controllers called the **GitOps Toolkit**. Unlike ArgoCD, which uses a centralized management model with a web console and an API server, Flux is highly decentralized, runs as individual controllers, and integrates directly with standard Kubernetes tools (like Kustomize and Helm).

---

## 🏛️ Microservice Controller Architecture

Flux is composed of specialized controllers. Each controller handles a specific Kubernetes Custom Resource Definition (CRD) and works as an independent microservice.

```
       +------------------+                   +------------------+
       |   Git / Helm /   |                   |  S3 / Container  |
       |    S3 Source     |                   |     Registry     |
       +--------+---------+                   +--------+---------+
                |                                      |
                +------------------+-------------------+
                                   |
                                   ▼
                        +----------------------+
                        |  Source Controller   |
                        +----------+-----------+
                                   |
                         (Caches raw tarballs)
                                   |
             +---------------------+---------------------+
             |                                           |
             ▼                                           ▼
+-------------------------+                 +-------------------------+
|  Kustomize Controller   |                 |     Helm Controller     |
+------------+------------+                 +------------+------------+
             |                                           |
    (Applies manifests)                        (Deploys Helm Charts)
             |                                           |
             +---------------------+---------------------+
                                   |
                                   ▼
                        +----------------------+
                        | Kubernetes API Server|
                        +----------+-----------+
                                   |
                            (Emits events)
                                   |
                                   ▼
                        +----------------------+
                        |Notification Controller|
                        +----------+-----------+
                                   |
                        (Slack, Webhooks, Teams)
```

### 1. Source Controller
The Source Controller is the entry point of the Flux GitOps loop. It fetches resources from remote providers, packages them into a gzip tarball artifact, and serves them locally to other controllers via an HTTP endpoint.
* **Supported Sources:** `GitRepository`, `HelmRepository`, `OCIRepository` (OCI registries like ECR/GHCR), and `Bucket` (Amazon S3, Google Cloud Storage).
* **Key Resource:** `GitRepository`

### 2. Kustomize Controller
The Kustomize Controller reconciles the state of a cluster with the raw manifests packaged by the Source Controller. It runs Kustomize overlays and applies the resources to the cluster.
* **Key Tasks:** Builds Kustomize directories, injects variables, decrypts secrets using Mozilla SOPS (supporting KMS, PGP, Vault), checks health of applied resources, and prunes unused resources.
* **Key Resource:** `Kustomization`

### 3. Helm Controller
The Helm Controller manages the deployment of Helm charts. It uses Helm's Go libraries directly inside the cluster, eliminating the need to install or run the `helm` CLI in external pipelines.
* **Key Tasks:** Evaluates Helm values, triggers Helm installation/upgrades, runs Helm test suites, and performs automatic rollbacks if tests or deployments fail.
* **Key Resource:** `HelmRelease`

### 4. Notification Controller
The Notification Controller handles inbound webhooks (to trigger immediate synchronization when Git changes) and outbound alerts (sending release statuses to Slack, Discord, MS Teams, GitHub commit statuses, or arbitrary endpoints).
* **Key Resources:** `Alert`, `Provider`, `Receiver`

---

## 🔒 Multi-Tenancy and Security Model

Flux was designed from the ground up to support highly secure multi-tenant clusters (where different teams share the same cluster).

### Service Account Impersonation
By default, GitOps controllers run with full cluster-admin access. In a multi-tenant cluster, this is dangerous because a developer could write a manifest in Git that elevates their permissions.
Flux solves this by allowing a `Kustomization` or `HelmRelease` to specify a `serviceAccountName`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: billing-team-deployment
  namespace: billing
spec:
  serviceAccountName: billing-deployer # <--- Impersonates this SA
  interval: 5m
  path: ./manifests
  sourceRef:
    kind: GitRepository
    name: billing-repo
```

When reconciling, the Kustomize Controller will impersonate the `billing-deployer` ServiceAccount. If the developer writes a manifest trying to deploy a `ClusterRole` or write to the `kube-system` namespace, the Kubernetes API server will reject the change with an authorization error.

---

## 🥾 The Bootstrap Concept

One of Flux's strongest features is its ability to **bootstrap** itself.
When you run the `flux bootstrap` command, the CLI does the following:

1. Connects to your Git repository provider (e.g., GitHub, GitLab).
2. Generates the Kubernetes manifests for the Flux controllers themselves.
3. Commits these controller manifests to your Git repository.
4. Applies the manifests to your cluster.
5. Configures a `GitRepository` and a `Kustomization` pointing to the repo where it was just committed.

From that moment on, **Flux manages itself**. To upgrade Flux, you don't run commands; you simply update the manifests in Git, and Flux applies its own updates.
