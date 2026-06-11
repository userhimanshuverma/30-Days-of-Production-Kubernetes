# 📊 Day 20 Architectural Diagrams: GitOps & Deployment Pipelines

This directory contains a centralized library of the 12 primary architectural workflows for Day 20, designed to make GitOps and progressive delivery processes visually intuitive.

---

## 🧭 Directory Index

* [1. End-to-End GitOps CI/CD Pipeline](#1-end-to-end-gitops-cicd-pipeline)
* [2. GitOps Reconciliation Loop](#2-gitops-reconciliation-loop)
* [3. ArgoCD Internal Architecture](#3-argocd-internal-architecture)
* [4. Flux v2 Internal Architecture](#4-flux-v2-internal-architecture)
* [5. Desired State Reconciliation Lifecycle](#5-desired-state-reconciliation-lifecycle)
* [6. Deployment Lifecycle](#6-deployment-lifecycle)
* [7. Drift Detection Workflow](#7-drift-detection-workflow)
* [8. Rollback Workflow](#8-rollback-workflow)
* [9. Multi-Environment Promotion Workflow](#9-multi-environment-promotion-workflow)
* [10. Multi-Cluster Production Deployment Architecture](#10-multi-cluster-production-deployment-architecture)
* [11. Blue/Green Deployment Strategy](#11-bluegreen-deployment-strategy)
* [12. Canary Deployment Strategy](#12-canary-deployment-strategy)

---

## 1. End-to-End GitOps CI/CD Pipeline

Describes the separation of code compilation/packaging (CI) and resource reconciliation (CD).

```mermaid
graph LR
    Dev[Developer] -->|1. Git Push| CodeRepo[App Code Repo]
    CodeRepo -->|2. Trigger| CI[CI Engine: GitHub Actions]
    CI -->|3. Build & Test| CI
    CI -->|4. Push Image| Registry[Image Registry: ECR/GAR]
    CI -->|5. Update Image Tag| ConfigRepo[GitOps Config Repo]
    
    subgraph K8s Cluster
        Agent[GitOps Operator: ArgoCD / Flux]
        K8sAPI[K8s API Server]
        Pods[Workloads / Pods]
    end
    
    ConfigRepo -.->|6. Pull Desired State| Agent
    Agent -->|7. Reconcile / Apply| K8sAPI
    K8sAPI -->|8. Create / Update| Pods
```

---

## 2. GitOps Reconciliation Loop

Visualizes the continuous check comparing desired configuration with real cluster state.

```mermaid
graph TD
    Git[Git Repository: Desired State] -->|Read Manifests| Loop{Reconciliation Loop}
    Cluster[K8s Cluster: Live State] -->|Read Resources| Loop
    Loop -->|Compare States| Diff{Is there a Diff?}
    Diff -->|No Diff: Synced| Sleep[Sleep & Wait for Poll/Webhook]
    Diff -->|Diff Detected: OutOfSync| Action{Auto-Heal Enabled?}
    Action -->|Yes| Heal[Over-write Cluster Live State with Git State]
    Action -->|No| Alert[Alert SRE / Mark Application OutOfSync]
    Heal --> Sleep
    Alert --> Sleep
```

---

## 3. ArgoCD Internal Architecture

Components within an ArgoCD namespace.

```mermaid
graph TB
    subgraph ArgoCD Namespace
        API[ArgoCD API Server]
        Repo[ArgoCD Repository Server]
        Ctrl[ArgoCD Application Controller]
        Redis[(Redis Cache)]
    end
    
    User[SRE / Developer] -->|CLI / UI / REST| API
    Git[Git / Helm Repos] <-->|Clones / Caches Manifests| Repo
    Repo <--> Redis
    Ctrl <--> Redis
    Ctrl -->|Polls Live State / Applies Desired State| K8s[K8s API Server]
    API --> Ctrl
```

---

## 4. Flux v2 Internal Architecture

The microservices model of Flux's GitOps Toolkit controllers.

```mermaid
graph TB
    Git[Git Repository] -->|Fetches Source| SourceCtrl[Source Controller]
    Helm[Helm Repository] -->|Fetches Charts| SourceCtrl
    
    subgraph GitOps Toolkit Controllers
        SourceCtrl -->|Artifacts| KustomizeCtrl[Kustomize Controller]
        SourceCtrl -->|Artifacts| HelmCtrl[Helm Controller]
        KustomizeCtrl -->|Applies Manifests| K8s[Kubernetes API Server]
        HelmCtrl -->|Applies Helm Releases| K8s
        
        K8s -->|Events| Reflect[Notification Controller]
    end
    
    Reflect -->|Slack / Teams / Discord| Alerts[SRE Alerts]
```

---

## 5. Desired State Reconciliation Lifecycle

A sequence of events demonstrating reconciliation steps.

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Platform Engineer
    participant Git as Git Repo
    participant CD as GitOps Controller
    participant K8s as K8s API Server
    
    Dev->>Git: Commit replicas: 3
    Git->>CD: Webhook notification (or Polling)
    CD->>Git: Fetch latest commit
    CD->>K8s: Query current running pods (found: 2)
    Note over CD: State Mismatch: Desired(3) != Live(2)
    CD->>K8s: PATCH deployment scale replicas to 3
    K8s->>CD: Deployment update acknowledged
    CD->>K8s: Query pods again (found: 3)
    Note over CD: Synced
```

---

## 6. Deployment Lifecycle

The states through which a resource passes during transition.

```mermaid
stateDiagram-v2
    [*] --> CodeCommitted: Developer merges Pull Request
    CodeCommitted --> CIBump: CI Builds image & tests pass
    CIBump --> TagUpdated: CI updates manifest repo image tag
    TagUpdated --> OutOfSync: GitOps detects new commit in Git
    OutOfSync --> Syncing: Controller begins applying resources
    Syncing --> HealthChecking: Pods terminating / starting
    HealthChecking --> Synced: Probes pass & replicas matching
    Synced --> [*]
```

---

## 7. Drift Detection Workflow

How manual kubectl edits are identified and processed.

```mermaid
graph TD
    A[SRE runs manual kubectl edit] --> B[K8s Live State Updates]
    B --> C[GitOps Controller compares Git vs K8s]
    C --> D{Is Live State == Git Desired State?}
    D -->|Yes| E[No Action]
    D -->|No| F[Drift Detected]
    F --> G{Self-Heal Active?}
    G -->|Yes| H[Apply Git desired state immediately]
    G -->|No| I[Mark App 'OutOfSync' & trigger Prometheus Alert]
```

---

## 8. Rollback Workflow

Reverting a failed application update in GitOps.

```mermaid
sequenceDiagram
    autonumber
    actor SRE
    participant Git as Git Repo
    participant CD as GitOps Controller
    participant K8s as K8s API Server
    
    SRE->>Git: Revert commit (git revert HEAD)
    Git->>CD: New Commit (Reverted State)
    CD->>Git: Fetch commit
    CD->>K8s: Apply reverted manifests
    Note over K8s: Rolling update starts backward
    K8s->>CD: Pods running successfully
    CD->>SRE: Application marked Synced
```

---

## 9. Multi-Environment Promotion Workflow

Steps to promote changes through gated quality environments.

```mermaid
graph TD
    Commit[Commit to Main Branch] --> DevDeploy[Auto Deploy to Dev Namespace]
    DevDeploy --> DevTests[Automated Integration Tests]
    DevTests -->|Pass| PRStaging[Create Promotion PR to Staging]
    PRStaging -->|Approve & Merge| StagingDeploy[Deploy to Staging Namespace]
    StagingDeploy --> LoadTests[Load / Performance Tests]
    LoadTests -->|Pass| PRProd[Create Promotion PR to Production]
    PRProd -->|SRE Review & Merge| ProdDeploy[Deploy to Production Namespace]
```

---

## 10. Multi-Cluster Production Deployment Architecture

Connecting multiple physical environments to a single controller.

```mermaid
graph TB
    subgraph Control Plane / Management Cluster
        Argo[Central ArgoCD Instance]
    end
    
    Git[Git Config Repo] -->|Polls Configuration| Argo
    
    subgraph Dev Cluster
        DevAPI[Dev K8s API] -->|Deploys to| DevNamespace[Dev Namespaces]
    end
    subgraph Staging Cluster
        StageAPI[Staging K8s API] -->|Deploys to| StageNamespace[Staging Namespaces]
    end
    subgraph Production Cluster
        ProdAPI[Production K8s API] -->|Deploys to| ProdNamespace[Prod Namespaces]
    end
    
    Argo -->|HTTPS/RBAC Cluster connection| DevAPI
    Argo -->|HTTPS/RBAC Cluster connection| StageAPI
    Argo -->|HTTPS/RBAC Cluster connection| ProdAPI
```

---

## 11. Blue/Green Deployment Strategy

Routing traffic between two physical releases.

```mermaid
graph TD
    Client[Client Traffic] -->|Route requests| Router[Kubernetes Service]
    Router -->|100% Traffic| Blue[Blue Deployment: V1 Pods]
    
    subgraph Active Production
        Blue
    end
    
    subgraph Isolated Staging
        Green[Green Deployment: V2 Pods]
    end
    
    Deploy[Deploy V2] --> Green
    Smoke[Smoke Tests Pass] -->|Switch Router Selector| Switch[Update Service Selector to Green]
    Switch -->|100% Traffic| Green
    Router -.->|0% Traffic| Blue
```

---

## 12. Canary Deployment Strategy

Exposing V2 to a percentage of requests and validating metrics.

```mermaid
graph TD
    Client[Client Traffic] -->|Route requests| Ingress[Ingress Controller: Envoy / NGINX]
    Ingress -->|90% Traffic| ServiceStable[Stable Service: V1 Pods]
    Ingress -->|10% Traffic| ServiceCanary[Canary Service: V2 Pods]
    
    subgraph Metrics Evaluation
        Prometheus[Prometheus Metrics] -->|Checks Error Rates & Latency| Controller[Canary Rollout Controller]
        Controller -->|Metrics Safe: Increase weight| Ingress
        Controller -->|Metrics Unsafe: Rollback to 0%| Ingress
    end
```
