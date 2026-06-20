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
* [Day 30 — Master Project: Build a Real Production-Grade Cloud-Native Platform](Day-30-Master-Project/README.md)

---

## 🗂️ Global SRE Reference Manuals
In addition to the 30-day curriculum, this repository provides global reference folders containing SRE templates, configs, and guides:

| Category | Reference Guide | Description |
| :--- | :--- | :--- |
| **AI & Compute** | [gpu-sharing-manifest.yaml](ai-infra/gpu-scheduling/gpu-sharing-manifest.yaml) | NVIDIA MPS GPU-sharing templates. |
| **Architecture** | [ha-topology.md](architecture/control-plane/ha-topology.md) \| [cni-comparison.md](architecture/networking/cni-comparison.md) | etcd consensus and CNI comparisons (Cilium vs Calico). |
| **Storage** | [csi-provisioning.md](architecture/storage/csi-provisioning.md) | CSI dynamics and Dynamic PV provisioning lifecycles. |
| **Case Studies** | [oom-postmortem.md](case-studies/OutOfMemory/oom-postmortem.md) | Incident post-mortem resolving JVM cgroup memory leaks. |
| **Quick Ref** | [kubectl-pro-cheatsheet.md](cheatsheets/kubectl-pro-cheatsheet.md) \| [kubernetes-glossary.md](glossary/kubernetes-glossary.md) | Advanced jsonpath commands and structural terms. |
| **CI/CD** | [argo-drift-prevention.md](ci-cd/argocd/argo-drift-prevention.md) \| [harden-github-actions.md](ci-cd/github-actions/harden-github-actions.md) | ArgoCD reconciliation and hardened GHA setups. |
| **Templates** | [production-deployment-template.yaml](templates/manifests/production-deployment-template.yaml) \| [boilerplate-chart/](helm/charts/boilerplate-chart/) | Hardened Deployment template and reusable Helm setups. |
| **Career** | [sre-k8s-interview-questions.md](interview-prep/sre-k8s-interview-questions.md) | Scenario-based interview prep sheet. |
| **Telemetry** | [prometheus-scraping.md](observability/prometheus/prometheus-scraping.md) \| [otel-collector-scaling.md](observability/otel/otel-collector-scaling.md) | Cardinality reductions and OTel tail-sampling guides. |
| **Security** | [pod-security-standards.yaml](security/policies/pod-security-standards.yaml) \| [sopps-pgp-secrets.md](security/secrets/sopps-pgp-secrets.md) | Namespace PSA labels and SOPS PGP encrypt guides. |

---

## 🛠️ Recommended Kubernetes Tooling
* **Local Cluster**: [Kind](https://kind.sigs.k8s.io/) or [Minikube](https://minikube.sigs.k8s.io/)
* **Cluster Management**: kubectl, k9s (Terminal UI)
* **Shell Helpers**: kubectx and kubens
* **Static Analysis and Linting**: yamllint, kubeconform, trivy

---

## 🤝 Contribution Guidelines
We welcome contributions! Please review our [CONTRIBUTING.md](CONTRIBUTING.md) to understand branch naming conventions, workflow validation, and formatting standards before sending pull requests.
