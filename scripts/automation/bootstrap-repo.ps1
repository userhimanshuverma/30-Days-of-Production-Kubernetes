# Bootstrap script for 30 Days of Production Kubernetes
# This script initializes the production-grade directory structure, template files, and configurations.

$rootPath = Resolve-Path ".."
$rootPath = $rootPath.Path
# If run from root, adjust:
if ($PSScriptRoot -eq "") {
    $rootPath = Get-Location
} else {
    $rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}

Write-Host "Initializing bootstrap in workspace root: $rootPath" -ForegroundColor Cyan

# Define Phase and Day Mapping (using standard hyphens and "and" to avoid encoding and shell expansion issues)
$days = @(
    @{ Id = "Day-01"; Phase = "PHASE 1 - FOUNDATIONS OF CLOUD-NATIVE SYSTEMS"; Title = "Why Kubernetes Changed Infrastructure Forever"; Summary = "Evolution from bare metal to containers, container orchestration needs, and K8s value." },
    @{ Id = "Day-02"; Phase = "PHASE 1 - FOUNDATIONS OF CLOUD-NATIVE SYSTEMS"; Title = "Containers Deep Dive"; Summary = "Namespaces, cgroups, runtimes (containerd), OCI standards, and container internals." },
    @{ Id = "Day-03"; Phase = "PHASE 1 - FOUNDATIONS OF CLOUD-NATIVE SYSTEMS"; Title = "Kubernetes Architecture Internals"; Summary = "API Server, Scheduler, Controller Manager, etcd, kubelet, and kube-proxy flows." },
    @{ Id = "Day-04"; Phase = "PHASE 1 - FOUNDATIONS OF CLOUD-NATIVE SYSTEMS"; Title = "Pods Explained Properly"; Summary = "Lifecycle, init containers, sidecars, multi-container patterns, and runtime specs." },
    @{ Id = "Day-05"; Phase = "PHASE 1 - FOUNDATIONS OF CLOUD-NATIVE SYSTEMS"; Title = "Deployments, ReplicaSets and Rollouts"; Summary = "Desired state model, self-healing, rolling updates, canary releases, and rollbacks." },
    @{ Id = "Day-06"; Phase = "PHASE 1 - FOUNDATIONS OF CLOUD-NATIVE SYSTEMS"; Title = "Services and Networking Fundamentals"; Summary = "ClusterIP, NodePort, LoadBalancer, DNS, service discovery, and kube-proxy internals." },
    @{ Id = "Day-07"; Phase = "PHASE 1 - FOUNDATIONS OF CLOUD-NATIVE SYSTEMS"; Title = "ConfigMaps, Secrets and Environment Management"; Summary = "Configuration separation, secrets protection, and External Secret Operator integration." },
    @{ Id = "Day-08"; Phase = "PHASE 2 - RUNNING REAL APPLICATIONS"; Title = "Persistent Storage and Volumes"; Summary = "PV, PVC, CSI specifications, storage classes, and local/cloud storage management." },
    @{ Id = "Day-09"; Phase = "PHASE 2 - RUNNING REAL APPLICATIONS"; Title = "StatefulSets and Distributed Databases"; Summary = "Stateful characteristics, network identity, head services, database deployments (Postgres/Kafka)." },
    @{ Id = "Day-10"; Phase = "PHASE 2 - RUNNING REAL APPLICATIONS"; Title = "Ingress and Traffic Routing"; Summary = "Ingress controllers, Ingress resources, TLS termination, and path-based routing." },
    @{ Id = "Day-11"; Phase = "PHASE 2 - RUNNING REAL APPLICATIONS"; Title = "Helm Deep Dive"; Summary = "Helm chart anatomy, templating, dry-runs, upgrades, and chart repositories." },
    @{ Id = "Day-12"; Phase = "PHASE 2 - RUNNING REAL APPLICATIONS"; Title = "Resource Management and Scheduling"; Summary = "CPU/Memory requests and limits, QoS classes (Guaranteed, Burstable, BestEffort), and Scheduler bin-packing." },
    @{ Id = "Day-13"; Phase = "PHASE 2 - RUNNING REAL APPLICATIONS"; Title = "Autoscaling in Production"; Summary = "Horizontal Pod Autoscaling (HPA), Vertical Pod Autoscaling (VPA), and Cluster Autoscaler." },
    @{ Id = "Day-14"; Phase = "PHASE 2 - RUNNING REAL APPLICATIONS"; Title = "Kubernetes Networking Internals"; Summary = "CNI interfaces, overlay networks, Calico, network policies, and pod-to-pod packet flow." },
    @{ Id = "Day-15"; Phase = "PHASE 2 - RUNNING REAL APPLICATIONS"; Title = "Kubernetes Security Fundamentals"; Summary = "RBAC (Roles, bindings), Service Accounts, Pod Security Standards (PSS/PSA), and Admission Control." },
    @{ Id = "Day-16"; Phase = "PHASE 3 - OBSERVABILITY AND PRODUCTION OPERATIONS"; Title = "Logging in Kubernetes"; Summary = "DaemonSet logging patterns, Fluent Bit, Loki, Prometheus-Operator logging, EFK stack." },
    @{ Id = "Day-17"; Phase = "PHASE 3 - OBSERVABILITY AND PRODUCTION OPERATIONS"; Title = "Monitoring with Prometheus and Grafana"; Summary = "Metrics collection, ServiceMonitors, Grafana dashboards, Prometheus Rules, alerting." },
    @{ Id = "Day-18"; Phase = "PHASE 3 - OBSERVABILITY AND PRODUCTION OPERATIONS"; Title = "Distributed Tracing and OpenTelemetry"; Summary = "OpenTelemetry collector, Jaeger, distributed context propagation, tracing microservices." },
    @{ Id = "Day-19"; Phase = "PHASE 3 - OBSERVABILITY AND PRODUCTION OPERATIONS"; Title = "Debugging Kubernetes Like a Production Engineer"; Summary = "CrashLoopBackOff, OOMKilled, ImagePullBackOff, network trace tools, ephemeral debug containers." },
    @{ Id = "Day-20"; Phase = "PHASE 3 - OBSERVABILITY AND PRODUCTION OPERATIONS"; Title = "CI/CD for Kubernetes"; Summary = "GitOps workflows, ArgoCD setup, declarative applications, sync strategies, and PR pipelines." },
    @{ Id = "Day-21"; Phase = "PHASE 3 - OBSERVABILITY AND PRODUCTION OPERATIONS"; Title = "Backup, Disaster Recovery and High Availability"; Summary = "etcd snapshotting and restore, Velero backups, multi-zone topology spread, HA control plane." },
    @{ Id = "Day-22"; Phase = "PHASE 4 - ADVANCED CLOUD-NATIVE ENGINEERING"; Title = "Kubernetes Scheduler Internals"; Summary = "Node affinity/anti-affinity, pod affinity/anti-affinity, taints, tolerations, and custom schedulers." },
    @{ Id = "Day-23"; Phase = "PHASE 4 - ADVANCED CLOUD-NATIVE ENGINEERING"; Title = "Service Mesh Deep Dive"; Summary = "Istio architecture, Envoy sidecars, traffic splitting, mTLS, and zero-trust mesh architectures." },
    @{ Id = "Day-24"; Phase = "PHASE 4 - ADVANCED CLOUD-NATIVE ENGINEERING"; Title = "Operators and Custom Resources"; Summary = "Custom Resource Definitions (CRDs), Operator SDK, controller loops, and automated operations." },
    @{ Id = "Day-25"; Phase = "PHASE 4 - ADVANCED CLOUD-NATIVE ENGINEERING"; Title = "Multi-Cluster Kubernetes"; Summary = "Multi-cluster management, cluster federation, global traffic management, and hybrid clouds." },
    @{ Id = "Day-26"; Phase = "PHASE 4 - ADVANCED CLOUD-NATIVE ENGINEERING"; Title = "GPU Workloads and AI Infrastructure"; Summary = "NVIDIA Device Plugin, GPU scheduling, MIG slicing, and LLM inference deployment on K8s." },
    @{ Id = "Day-27"; Phase = "PHASE 4 - ADVANCED CLOUD-NATIVE ENGINEERING"; Title = "Running Data Platforms on Kubernetes"; Summary = "Spark operator, Apache Airflow scheduling, Apache Kafka cluster running stateful configurations." },
    @{ Id = "Day-28"; Phase = "PHASE 5 - REAL PRODUCTION SYSTEMS"; Title = "Designing Production-Grade Kubernetes Architecture"; Summary = "High-availability, VPC networking, cross-AZ node pools, and reference architectures." },
    @{ Id = "Day-29"; Phase = "PHASE 5 - REAL PRODUCTION SYSTEMS"; Title = "Cost Optimization and Performance Engineering"; Summary = "Right-sizing (Karpenter), Spot instances, cluster overprovisioning, and Linux kernel tuning." },
    @{ Id = "Day-30"; Phase = "PHASE 5 - REAL PRODUCTION SYSTEMS"; Title = "MASTER PROJECT: Deploy and Operate a Scalable Production Platform End-to-End"; Summary = "Multi-tier HA application deployment, monitoring stack, security hardening, and autoscaling." }
)

# Global Folders to Initialize
$globalFolders = @(
    "assets/branding",
    "assets/diagrams",
    "architecture/control-plane",
    "architecture/networking",
    "architecture/storage",
    "observability/prometheus",
    "observability/grafana",
    "observability/otel",
    "security/rbac",
    "security/policies",
    "security/secrets",
    "ci-cd/argocd",
    "ci-cd/github-actions",
    "helm/charts",
    "ai-infra/gpu-scheduling",
    "case-studies/OutOfMemory",
    "cheatsheets",
    "templates/manifests",
    "templates/charts",
    "scripts/automation",
    "scripts/cluster-setup",
    "projects/mini-projects",
    "projects/master-project",
    "interview-prep",
    "glossary"
)

# Create Global Folders
foreach ($folder in $globalFolders) {
    $path = Join-Path $rootPath $folder
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "Created global directory: $folder" -ForegroundColor Green
    }
    # Create standard placeholders
    $keepPath = Join-Path $path ".gitkeep"
    if (!(Test-Path $keepPath)) {
        New-Item -ItemType File -Path $keepPath -Force | Out-Null
    }
}

# Create Day-wise Folders
foreach ($day in $days) {
    $dayId = $day.Id
    $dayPath = Join-Path $rootPath $dayId
    Write-Host "Creating structure for $($dayId): $($day.Title)" -ForegroundColor Yellow
    
    # Subdirectories for each day
    $subfolders = @("notes", "diagrams", "manifests", "labs", "exercises", "production-notes", "troubleshooting", "resources")
    foreach ($sub in $subfolders) {
        $subPath = Join-Path $dayPath $sub
        if (!(Test-Path $subPath)) {
            New-Item -ItemType Directory -Path $subPath -Force | Out-Null
        }
        $keep = Join-Path $subPath ".gitkeep"
        if (!(Test-Path $keep)) {
            New-Item -ItemType File -Path $keep -Force | Out-Null
        }
    }
    
    # Create Day README.md
    $dayReadmePath = Join-Path $dayPath "README.md"
    if (!(Test-Path $dayReadmePath)) {
        $readmeContent = @"
# 📖 $($day.Id) - $($day.Title)
### 🏷️ $($day.Phase)

> **TL;DR:** $($day.Summary)

---

## 🎯 Learning Objectives
By the end of this day, you will be able to:
1. Explain the architectural concepts of **$($day.Title)**.
2. Troubleshoot and solve primary issues related to this domain.
3. Configure, deploy, and inspect manifests in a running Kubernetes environment.
4. Relate these concepts to enterprise and production environment scaling challenges.

---

## 📝 Core Concepts
*Theoretical deep dives, diagrams, and reference guides can be found in the [notes/](notes/) directory.*

* **Key Topic 1:** Core definition and architectural positioning.
* **Key Topic 2:** Communication path and workflow dependencies.
* **Key Topic 3:** Common design trade-offs and operational best practices.

---

## 🛠️ Hands-On Lab Walkthrough
*Step-by-step guides can be found in the [labs/](labs/) directory.*

### Prerequisites
* A running Kubernetes Cluster (Kind, Minikube, or custom dev cluster)
* `kubectl` CLI installed and configured.

### Lab Steps
1. **Apply configurations:**
   ```bash
   kubectl apply -f manifests/
   ```
2. **Inspect and Verify:**
   ```bash
   kubectl get all -n default
   ```
3. **Validate logs and debug states:**
   ```bash
   kubectl logs <pod-name>
   ```

---

## ⚡ Production Considerations and Hardening
*Deep operational notes are located in the [production-notes/](production-notes/) directory.*

* **Security:** Pod security, RBAC scope limits, and resource quotas.
* **Performance:** Resource limits and horizontal autoscaling rules.
* **Reliability:** Liveness, readiness, and startup probe definitions.

---

## 🚨 Troubleshooting and Debugging Playbook
*Comprehensive troubleshooting runbooks can be found in the [troubleshooting/](troubleshooting/) directory.*

| Common Error | Likely Cause | Solution & Diagnostics Command |
|---|---|---|
| `Error/CrashLoopBackOff` | Configuration mismatch or missing dependency | `kubectl describe pod` / `kubectl logs` |
| `ImagePullBackOff` | Private registry credential error or typo | Check Secret definition and image tags |

---

## 🏆 Daily Assignment and Challenge
*Details and code challenges can be found in the [exercises/](exercises/) directory.*

* **Challenge:** Implement the scenario details inside the exercise manifest, verify using local kind cluster and capture logs demonstrating deployment success.

---

## 📚 References and Recommended Reading
*See details in [resources/](resources/) directory.*

* [Kubernetes Documentation](https://kubernetes.io/docs/)
* Production guidelines and reference blogs.
"@
        Set-Content -Path $dayReadmePath -Value $readmeContent -Encoding utf8
    }
}

# Create .gitignore
$gitignorePath = Join-Path $rootPath ".gitignore"
if (!(Test-Path $gitignorePath)) {
    $gitignoreContent = @"
# OS-specific files
.DS_Store
Thumbs.db
desktop.ini

# IDEs and Editors
.idea/
.vscode/
*.suo
*.ntvs*
*.njsproj
*.sln
*.swp

# Kubernetes and Helm outputs
.kube/
kubeconfig
*.kubeconfig
.helm/
*.tgz
charts/logs/

# Terraform state
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl

# Local secrets and credentials
*.pem
*.key
*.crt
credentials.json
.env
secret-*.yaml
!*example*secret*.yaml

# Temporary outputs
tmp/
temp/
logs/
*.log
"@
    Set-Content -Path $gitignorePath -Value $gitignoreContent -Encoding utf8
    Write-Host "Created .gitignore" -ForegroundColor Green
}

# Create CONTRIBUTING.md
$contributingPath = Join-Path $rootPath "CONTRIBUTING.md"
if (!(Test-Path $contributingPath)) {
    $contributingContent = @"
# 🤝 Contributing to 30 Days of Production Kubernetes

Thank you for helping build the premier open-source Kubernetes learning repository! To maintain our high engineering and content standards, please follow these guidelines.

## 🚀 How to Contribute

1. **Fork the Repository** to your personal GitHub account.
2. **Create a Feature Branch** from `main`:
   ```bash
   git checkout -b feature/day-xx-short-description
   ```
3. **Commit your changes** following the [Conventional Commits](https://www.conventionalcommits.org/) standard:
   * `feat(day-15): add rbac manifests`
   * `fix(day-03): fix typo in etcd scheduler writeup`
   * `docs(day-09): add database replication diagram`
4. **Push to your fork** and submit a **Pull Request**.

## 📏 Content and Engineering Standards

* **Manifests**: Ensure all YAML manifests are valid, conform to K8s schemas, and follow our naming order (e.g. `01-namespace.yaml`, `02-deployment.yaml`).
* **YAML Formatting**:
  * 2 spaces indentation.
  * No tabs.
  * Explicit resource limits and readiness/liveness probes where applicable.
* **Documentation**:
  * Use clear headings and clean Markdown.
  * Embed diagrams using Mermaid.js or store SVGs in `Day-XX/diagrams/`.
  * Highlight production-grade choices (e.g., security considerations, HA config).

## 🛡️ Pull Request Quality Gates
Before your pull request is merged, it will be validated using:
1. **Yamllint**: Verify structural syntax of all manifest files.
2. **Kubeconform**: Verify YAML declarations against official Kubernetes API schemas.
"@
    Set-Content -Path $contributingPath -Value $contributingContent -Encoding utf8
    Write-Host "Created CONTRIBUTING.md" -ForegroundColor Green
}

# Create Root README.md
$readmePath = Join-Path $rootPath "README.md"
if (!(Test-Path $readmePath)) {
    $readmeContent = @"
# 🚀 30 Days of Production Kubernetes

Welcome to the premier open-source repository designed to take you from Kubernetes beginner to senior production platform engineer. This repo is a complete, hands-on syllabus, knowledge base, and production blueprint.

---

## 🗺️ Roadmap and Syllabus

### Phase 1: Foundations of Cloud-Native Systems
* [Day 01 — Why Kubernetes Changed Infrastructure Forever](Day-01/README.md)
* [Day 02 — Containers Deep Dive](Day-02/README.md)
* [Day 03 — Kubernetes Architecture Internals](Day-03/README.md)
* [Day 04 — Pods Explained Properly](Day-04/README.md)
* [Day 05 — Deployments, ReplicaSets and Rollouts](Day-05/README.md)
* [Day 06 — Services and Networking Fundamentals](Day-06/README.md)
* [Day 07 — ConfigMaps, Secrets and Environment Management](Day-07/README.md)

### Phase 2: Running Real Applications
* [Day 08 — Persistent Storage and Volumes](Day-08/README.md)
* [Day 09 — StatefulSets and Distributed Databases](Day-09/README.md)
* [Day 10 — Ingress and Traffic Routing](Day-10/README.md)
* [Day 11 — Helm Deep Dive](Day-11/README.md)
* [Day 12 — Resource Management and Scheduling](Day-12/README.md)
* [Day 13 — Autoscaling in Production](Day-13/README.md)
* [Day 14 — Kubernetes Networking Internals](Day-14/README.md)
* [Day 15 — Kubernetes Security Fundamentals](Day-15/README.md)

### Phase 3: Observability and Production Operations
* [Day 16 — Logging in Kubernetes](Day-16/README.md)
* [Day 17 — Monitoring with Prometheus and Grafana](Day-17/README.md)
* [Day 18 — Distributed Tracing and OpenTelemetry](Day-18/README.md)
* [Day 19 — Debugging Kubernetes Like a Production Engineer](Day-19/README.md)
* [Day 20 — CI/CD for Kubernetes](Day-20/README.md)
* [Day 21 — Backup, Disaster Recovery and High Availability](Day-21/README.md)

### Phase 4: Advanced Cloud-Native Engineering
* [Day 22 — Kubernetes Scheduler Internals](Day-22/README.md)
* [Day 23 — Service Mesh Deep Dive](Day-23/README.md)
* [Day 24 — Operators and Custom Resources](Day-24/README.md)
* [Day 25 — Multi-Cluster Kubernetes](Day-25/README.md)
* [Day 26 — GPU Workloads and AI Infrastructure](Day-26/README.md)
* [Day 27 — Running Data Platforms on Kubernetes](Day-27/README.md)

### Phase 5: Real Production Systems
* [Day 28 — Designing Production-Grade Kubernetes Architecture](Day-28/README.md)
* [Day 29 — Cost Optimization and Performance Engineering](Day-29/README.md)
* [Day 30 — Master Project: Deploy and Operate a Production Platform](Day-30/README.md)

---

## 🛠️ Recommended Kubernetes Tooling
* **Local Cluster**: [Kind](https://kind.sigs.k8s.io/) or [Minikube](https://minikube.sigs.k8s.io/)
* **Cluster Management**: `kubectl`, `k9s` (Terminal UI)
* **Shell Helpers**: `kubectx` and `kubens`
* **Static Analysis and Linting**: `yamllint`, `kubeconform`, `trivy`

---

## 🤝 Contribution Guidelines
We welcome contributions! Please review our [CONTRIBUTING.md](CONTRIBUTING.md) to understand branch naming conventions, workflow validation, and formatting standards before sending pull requests.
"@
    Set-Content -Path $readmePath -Value $readmeContent -Encoding utf8
    Write-Host "Created root README.md" -ForegroundColor Green
}

Write-Host "Bootstrap completed successfully!" -ForegroundColor Cyan
