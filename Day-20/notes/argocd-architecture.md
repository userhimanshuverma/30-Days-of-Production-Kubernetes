# 📔 ArgoCD Deep Dive: Internal Architecture & Custom Resources

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. It runs inside the cluster and synchronizes manifests with a Git repository. To run ArgoCD in production, you must understand its underlying components and CRDs.

---

## 🏛️ Component Architecture

ArgoCD is not a single binary; it is comprised of several microservices, each with a specific responsibility.

```
                  +----------------------------------------------+
                  |                 ArgoCD Web UI / CLI / API    |
                  +----------------------+-----------------------+
                                         |
                                         ▼
                  +----------------------------------------------+
                  |              ArgoCD API Server               |
                  +----------------------+-----------------------+
                                         |
                                         ▼
  +--------------------------------------+--------------------------------------+
  |                                                                             |
  ▼                                                                             ▼
+--------------------------------------+                              +--------------------------------------+
|        ArgoCD Repo Server            |                              |     ArgoCD Application Controller    |
+------------------+-------------------+                              +------------------+-------------------+
                   |                                                                     |
                   v (Caches manifests)                                                  v (Polls state & applies)
+------------------+-------------------+                                                 |
|             Redis Cache              |<------------------------------------------------+
+--------------------------------------+                                                 |
                                                                                         ▼
                                                                              +--------------------------------------+
                                                                              |       Kubernetes API Server          |
                                                                              +--------------------------------------+
```

### 1. ArgoCD API Server
The API Server handles authentication, RBAC authorization, and API routing. It powers the ArgoCD Web UI, the CLI, and external tools (like Terraform provider or CI webhooks).
* **Key Tasks:** SSO integrations (OIDC, Dex), user session management, project authorization checks, and proxying operations to other controllers.

### 2. ArgoCD Repository Server
The Repository Server maintains a local cache of Git repositories containing application manifests.
* **Key Tasks:** Clones Git repos, monitors remote repositories for new commits, runs templating tools (like `kustomize build` or `helm template`), and caches generated raw YAML manifests in Redis.
* **Production Tip:** Under high load (many repositories and frequent commits), the Repository Server can become CPU-bound due to running JS/Go templating engines. You should scale this deployment horizontally in large environments.

### 3. ArgoCD Application Controller
The Application Controller is the brain of ArgoCD. It is a Kubernetes Controller that constantly compares the live state of the target Kubernetes cluster with the desired state cached by the Repository Server.
* **Key Tasks:** Observes resource drift using Kubernetes Informers, executes sync logic (creates, updates, prunes resources), runs sync waves and hooks, and updates the health status of applications.

### 4. Redis
Used as a caching layer for Git repository checkouts, generated manifests, and cluster resource details to prevent rate-limiting from GitHub/GitLab and high CPU consumption in the repository server.

---

## 📄 Core Custom Resource Definitions (CRDs)

ArgoCD introduces three main CRDs to manage applications:

### 1. `Application`
The `Application` resource links a manifest source (Git/Helm) to a destination (Kubernetes Cluster + Namespace).
* **Essential fields:**
  * `spec.source`: Repo URL, revision (tag, branch, commit SHA), and folder path.
  * `spec.destination`: Target Kubernetes cluster URL (or name) and target namespace.
  * `spec.syncPolicy`: Defines if sync should be manual or automated, and rules for self-healing and pruning.

### 2. `AppProject`
An `AppProject` provides a logical boundary for managing multiple `Application` resources. It is critical for multi-tenant platform configurations.
* **Controls:**
  * Which Git source repositories are allowed.
  * Which target clusters and namespaces applications can deploy to.
  * Which Kubernetes resource kinds can be created (e.g., you can block Applications in a project from creating ClusterRoles).
  * Role-based access control (RBAC) rules mapped to specific SSO groups.

### 3. `ApplicationSet`
An `ApplicationSet` uses template generators to dynamically deploy multiple ArgoCD `Application` instances.
* **Generators:**
  * **List Generator:** Loops through a hardcoded list of clusters/namespaces.
  * **Git Generator:** Scans directories in a Git repository and creates an application for each subfolder containing manifests.
  * **Cluster Generator:** Scans all clusters registered in ArgoCD and deploys the application across all of them (perfect for deploying agent-like tools such as Prometheus Node Exporters).

---

## ⚡ Sync Engine Mechanics

When ArgoCD reconciles manifests, it executes several features to guarantee safe rollouts:

### 1. Sync Waves
By default, Kubernetes applies manifests in arbitrary order. In production, however, you may need a Database schema migration to complete *before* you update the Web Pods. ArgoCD solves this using Sync Waves.
You add an annotation to your manifests:
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "5"
```
ArgoCD applies resources in ascending order of their wave numbers (e.g., wave `-1` runs first, wave `0` runs next, wave `5` follows). It waits for all resources in wave `n` to be healthy before proceeding to wave `n+1`.

### 2. Sync Hooks
Hooks run at specific lifecycle phases of the synchronization. Common hooks include `PreSync` (database backups), `PostSync` (slack alerts, integration tests), and `SyncFail` (rollback alerts).
```yaml
metadata:
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
```

### 3. Pruning and Self-Healing
* **Pruning:** If you delete a manifest from Git, Kubernetes doesn't automatically delete the live resource. ArgoCD's pruning engine identifies that the resource exists in the cluster but no longer exists in Git and deletes it.
* **Self-Healing:** If someone runs `kubectl edit` in the cluster, ArgoCD flags the resource as `OutOfSync`. If `selfHeal` is enabled, the controller automatically patches the cluster resource to match the configuration defined in Git.
