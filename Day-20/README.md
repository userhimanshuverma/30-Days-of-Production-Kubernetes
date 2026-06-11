# 📖 Day 20 - CI/CD and GitOps for Production Kubernetes
### 🏷️ PHASE 3 - OBSERVABILITY & PRODUCTION OPERATIONS

Welcome to Day 20. Today, we bridge the gap between building application manifests and operating them at scale. In production, the question is not *"How do I run this container?"* but *"How do I deploy 500 microservices across 10 clusters without human error, credential exposure, or configuration drift?"*

We will dismantle the traditional "push-based" pipelines and reconstruct them using modern **GitOps** paradigms with **ArgoCD** and **Flux**. By the end of this day, you will never want to run `kubectl apply` manually again.

---

## 🎯 Learning Objectives

By the end of this day, you will deeply understand:
1. Why traditional "push-based" deployment pipelines fail under production scaling.
2. The core principles of GitOps and pull-based reconciliation.
3. The internal architectures of ArgoCD and Flux.
4. Desired state reconciliation, drift detection, and automated self-healing.
5. Production progressive delivery strategies (Rolling, Blue/Green, Canary).
6. Multi-environment promotion workflows (Dev -> Staging -> Prod) using Kustomize and Git branches/folders.

---

## 🛑 Why Traditional Deployments Break at Scale

In the early days of Kubernetes, developers and SREs deployed applications using shell scripts or standard CI pipelines (Jenkins, GitLab CI, GitHub Actions) running:
```bash
kubectl apply -f manifests/deployment.yaml --namespace production
```

While this works for simple workloads, it introduces fatal flaws in enterprise production:

### 1. The Security Nightmare (Credential Exposure)
To run `kubectl apply`, your CI pipeline needs cluster-admin credentials (kubeconfig or service account tokens). If your CI runner is compromised, the attacker gains full administrative access to your production Kubernetes cluster.

### 2. Configuration Drift (The Silent Killer)
Imagine a developer debugs an outage at 3 AM. They run:
```bash
kubectl scale deployment/payment-service --replicas=10 -n production
```
This change lives only in the cluster's live memory. The next time the CI pipeline runs, or if the pod is rescheduled, the cluster reverts to the old configuration stored in Git. Conversely, someone could manually modify a ConfigMap, and because Git is unaware of it, the system enters an untracked, unstable state.

### 3. Lack of Auditability and Rollback Gaps
Who changed the resource limits on `auth-service`? When? Why?
In a push-based model, audit logs are scattered across CI jobs, cloud provider IAM logs, and Kubernetes API logs. Rolling back requires finding a previous CI build and rerunning it, hoping no manifests have changed in the meantime.

---

## 🔄 CI/CD Fundamentals: Push vs. Pull

A modern deployment pipeline separates **Continuous Integration (CI)** from **Continuous Delivery/Deployment (CD)**.

### Traditional Push-Based CI/CD
In a push-based system, the CI tool compiles, tests, packages, and directly "pushes" the changes into the Kubernetes API.
```
[ Developer ] ──> [ Git Repo ] ──> [ CI Server (GitHub Actions) ] ──( kubectl apply )──> [ Kubernetes API ]
```

### Modern Pull-Based GitOps
In a pull-based (GitOps) system, the CI pipeline stops at the registry. An agent inside the Kubernetes cluster constantly pulls the desired state from Git.
```
[ Developer ] ──> [ Git Repo ] ──> [ CI Server ] ──> [ Image Registry ]
                                          │
                               (Updates Config Repo)
                                          │
                                          ▼
                                   [ Config Repo ]
                                          ▲
                                          │ (Pulls & Reconciles)
                                   [ GitOps Agent ] ──> [ Kubernetes API ]
```

---

## 📊 Visualizing the Architecture (Mermaid Diagrams)

Here are the visual blueprints explaining how these systems work in production.

### 1. The End-to-End GitOps CI/CD Pipeline
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

### 2. GitOps Reconciliation Loop
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

### 3. ArgoCD Internal Architecture
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

### 4. Flux v2 Internal Architecture (GitOps Toolkit)
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

### 5. Desired State Reconciliation Lifecycle
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

### 6. Deployment Lifecycle (Code to Cluster)
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

### 7. Drift Detection Workflow
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

### 8. Rollback Workflow (GitOps Style)
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

### 9. Multi-Environment Promotion Workflow
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

### 10. Multi-Cluster Production Deployment Architecture
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

### 11. Blue/Green Deployment Strategy
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

### 12. Canary Deployment Strategy
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

---

## 🛠️ GitOps Tools Deep Dive: ArgoCD vs. Flux

Although both tools implement GitOps, their architecture and operations differ significantly.

| Feature | ArgoCD | Flux v2 |
| :--- | :--- | :--- |
| **Architecture** | Monolithic control plane, API server, Redis cache, Web UI. | Microservices based, GitOps Toolkit, Kubernetes-native controllers. |
| **User Interface** | Outstanding, rich real-time visual web dashboard. | CLI first (GitOps CLI). Third-party UIs (Weave Gitops) exist. |
| **Multi-tenancy** | Managed via AppProjects with built-in RBAC/SSO. | Managed using native Kubernetes namespaces, RBAC, and ServiceAccounts. |
| **Sync Model** | Pushes to targeted clusters from a central instance (Hub-and-Spoke). | Pulled locally inside each cluster (highly decentralized and secure). |
| **Templating** | Helm, Kustomize, Jsonnet, Raw YAML out of the box. | Native Kustomize and Helm controllers. |

---

## 🚀 Deployment Strategies

When deploying updates to your applications, you must choose a deployment strategy to minimize downtime and risk.

### 1. Rolling Update (Default)
Kubernetes spins up new replica pods (V2) while gradually terminating old ones (V1).
* **Pros:** Simple, built-in, no extra resources needed.
* **Cons:** No control over traffic shifting (users hit both versions simultaneously). Hard to roll back instantly if a database migration error occurs.

### 2. Blue/Green
You run two identical environments: Blue (current production) and Green (new release). Once Green passes testing, traffic is cut over.
* **Pros:** Zero downtime. Immediate rollback (just point the router/service back to Blue).
* **Cons:** Double the infrastructure cost during deployment.

### 3. Canary
You route a tiny slice of real traffic (e.g., 5%) to the new release (Canary). You observe telemetry (HTTP 5xx, latency). If healthy, you scale the canary and route more traffic.
* **Pros:** High safety margin. Tests new code with real production traffic.
* **Cons:** Complex configuration. Requires advanced Ingress controllers (Istio, Linkerd, NGINX) and automated metric analysis (e.g., Argo Rollouts, Flux Flagger).

---

## 🧑‍💻 Production Code Snippets

Let's look at how we declaratively configure GitOps resources.

### ArgoCD Application manifest
This resource tells ArgoCD where to look for Kubernetes manifests in Git and where to deploy them.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: payment-service-production
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/userhimanshuverma/30-Days-of-Production-Kubernetes.git'
    targetRevision: main
    path: Day-20/manifests
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Flux Kustomization manifest
This resource tells Flux's Kustomize controller how to apply manifests downloaded by the source controller.

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: payment-service-prod
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./Day-20/manifests
  prune: true
  sourceRef:
    kind: GitRepository
    name: main-config
  targetNamespace: production
```

---

## 🧪 Interactive Learning

We have built an enterprise-grade simulator to help you visualize these concepts live.

### GitOps Control Center Simulation
Open [gitops-control-center.html](file:///d:/30_Days_of_Production_Kubernetes/Day-20/gitops-control-center.html) in your browser. This custom UI lets you:
* Commit code and watch the CI pipeline package and update the manifest repo.
* Observe ArgoCD / Flux pulling the changes and spinning up pods.
* **Simulate Configuration Drift:** Edit the live pods manually (simulating a `kubectl edit`), watch the controller immediately flag it as `OutOfSync`, and execute auto-healing.
* Test Progressive Delivery options (Canary/Blue-Green) and witness how service selectors shift traffic dynamically.

---

## 📂 Day-20 Directory Map

Explore the directories to complete today's curriculum:

* 📔 [notes/](notes/): Deep dives on [CI/CD Fundamentals](notes/ci-cd-fundamentals.md), [ArgoCD Core Architecture](notes/argocd-architecture.md), [Flux GitOps Toolkit](notes/flux-architecture.md), and [Deployment Strategies](notes/deployment-strategies.md).
* ⚙️ [manifests/](manifests/): Production-grade microservice Kubernetes definitions.
* 📦 [argocd/](argocd/): ArgoCD custom applications and project rules.
* 🌿 [flux/](flux/): Flux GitRepository and Kustomization definitions.
* 🔬 [labs/](labs/): 6 step-by-step production labs (from basic installs to multi-env promotion). Read [labs/README.md](labs/README.md) to start.
* 🛑 [troubleshooting/](troubleshooting/): Production Incident Runbook resolving common ArgoCD/Flux sync errors.
* 🧠 [exercises/](exercises/): SRE assignments to configure automated drift recovery.
* 📖 [production-notes/](production-notes/): Senior platform engineer handbook on Secrets management and GitOps scaling.
