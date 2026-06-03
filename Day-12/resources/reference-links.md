# 📚 References and Recommended Readings

Here is a curated list of research papers, official documentation, and open-source tools to deepen your knowledge of Kubernetes scheduling and resource management.

---

## Research Papers on Large-Scale Scheduler Design
1. **Large-scale cluster management at Google with Borg (2015)**
   - The foundation of Kubernetes. Understands how Google manages millions of containers using Borg and its scheduler.
   - [Read Borg Paper](https://research.google/pubs/large-scale-cluster-management-at-google-with-borg/)
2. **Omega: flexible, scalable schedulers for large compute clusters (2013)**
   - Explores optimistic concurrency control scheduling models that inspired the Kubernetes scheduler cache.
   - [Read Omega Paper](https://research.google/pubs/omega-flexible-scalable-schedulers-for-large-compute-clusters/)

---

## Official Kubernetes Documentation
- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes Scheduler Mechanics](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)
- [Configure Quality of Service (QoS) for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/assign-cpu-memory-resources/)
- [Limit Ranges in Kubernetes](https://kubernetes.io/docs/concepts/policy/limitrange/)
- [Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)

---

## Open Source Cost Optimization and Autoscaling Tools
- **Karpenter:** A high-performance Kubernetes node autoscaler built by AWS that provisions nodes dynamically based on pending Pod requirements.
  - [Karpenter Project](https://karpenter.sh/)
- **Kubecost:** Live cost monitoring and allocation metrics directly mapping Kubernetes requests and usage to real-world cloud spend.
  - [Kubecost Project](https://www.kubecost.com/)
- **Goldilocks:** An open-source utility that aggregates vertical pod autoscaler recommendation data to recommend realistic requests and limits.
  - [Goldilocks GitHub](https://github.com/FairwindsOps/goldilocks)
