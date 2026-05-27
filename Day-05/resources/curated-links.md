# 📚 Day 5 Curated Resources: Deployments, Rollouts & Delivery

This document lists recommended reading, tools, and official references to deepen your understanding of Kubernetes workloads, control loops, and progressive delivery practices.

---

## 📖 Official Kubernetes Documentation
* [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) — Official conceptual guide and API specs.
* [Kubernetes ReplicaSets](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/) — Understanding ReplicaSet scaling and label matching.
* [Configure Liveness, Readiness, and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/) — Detailed steps to configure container health checks.
* [Pod Disruption Budgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) — Protecting workloads from voluntary node disruptions.

---

## 🛠️ Progressive Delivery & Canary Tools
* [Argo Rollouts](https://argoproj.github.io/argo-rollouts/) — A Kubernetes controller and CRD that provides advanced deployment capabilities (Canary, Blue/Green, analysis, metrics integration).
* [Flagger](https://flagger.app/) — A progressive delivery operator that automates canary rollouts using Istio, Linkerd, App Mesh, Nginx Ingress, etc.
* [Karpenter](https://karpenter.sh/) — A node-autoscaler that integrates with Kubernetes scheduling constraints (affinity, topology spread) to scale capacity quickly.

---

## 🧠 Articles & Deep Dives
* [A Visual Guide to Kubernetes Deployment Strategies](https://container-solutions.com visual-guide-to-kubernetes-deployment-strategies/) — Graphic comparisons of Recreate, RollingUpdate, Blue/Green, Canary, and Shadow deployments.
* [Kubernetes Probes: The Good, The Bad, and The Ugly](https://sysdig.com/blog/kubernetes-probes/) — Guidelines on avoiding common mistakes in startup, readiness, and liveness configurations.
* [The expand/contract database migration pattern](https://martinfowler.com/articles/evobuzz.html) — Evolution of database schema in high-availability environments.
* [Under the hood of the Kube-Controller-Manager](https://github.com/kubernetes/community/blob/master/contributors/devel/sig-architecture/api-conventions.md) — Architectural guidelines for controller builders.
