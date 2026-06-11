# 🧪 Day 20 Hands-on Labs: GitOps in Practice

Welcome to the hands-on lab suite for Day 20. These labs are designed to take you from a raw Kubernetes cluster to operating fully automated, drift-detecting, self-healing GitOps pipelines using both ArgoCD and Flux v2.

---

## 🛠️ Prerequisites & Lab Environment

Before beginning, ensure you have the following installed on your local workstation:

1. **Kubernetes Cluster:** A local running cluster (e.g., [Kind](https://kind.sigs.k8s.io/) or [Minikube](https://minikube.sigs.k8s.io/)).
   * If using Kind, create a cluster:
     ```bash
     kind create cluster --name gitops-day20
     ```
2. **CLIs Installed:**
   * `kubectl` (v1.26+)
   * `helm` (v3.x)
   * `git`
3. **Git Repository:** Access to a Git hosting provider (e.g., GitHub, GitLab, Gitea) and personal access tokens (PAT) for auth.

---

## 🧭 Lab Index

We suggest executing these labs in order:

### 1. [Lab 1: Installing ArgoCD and Flux v2](lab-1-install-argocd-flux.md)
* Learn how to bootstrap the control planes for both GitOps tools.
* Expose and log into the ArgoCD dashboard.

### 2. [Lab 2: Deploying Applications via ArgoCD](lab-2-deploy-app-argocd.md)
* Configure a secure namespace and deploy our first microservice using an ArgoCD declarative Application manifest.

### 3. [Lab 3: Bootstrapping and Deploying via Flux v2](lab-3-deploy-app-flux.md)
* Use the Flux CLI to bootstrap your Kubernetes cluster directly against a Git repository.
* Reconcile workloads using Flux `GitRepository` and `Kustomization` resources.

### 4. [Lab 4: Drift Detection & Automated Reconciliation](lab-4-drift-detection-reconciliation.md)
* Intentionally break the golden rule by running manual `kubectl edit` actions.
* Witness how ArgoCD and Flux detect the drift and automatically correct it (self-healing).

### 5. [Lab 5: Declarative Helm Deployments via GitOps](lab-5-helm-via-gitops.md)
* Deploy packages using Helm charts without running local `helm install` commands.
* Define upgrades and values overrides declaratively.

### 6. [Lab 6: Multi-Environment Promotion Workflows](lab-6-multi-env-promotion.md)
* Configure Kustomize base and environment overlays (Staging, Production).
* Simulate promotion pipelines using Pull Request reviews and approvals.
