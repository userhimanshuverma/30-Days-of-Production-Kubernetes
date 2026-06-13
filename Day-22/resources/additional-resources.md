# 📚 Recommended Reading & Production Tooling

Expand your knowledge of Kubernetes scheduling with these official resources and open-source platform engineering tools.

---

## 🔧 Production Tools

1. **[Kube-Descheduler](https://github.com/kubernetes-sigs/descheduler)**:
   * *What it does*: The default scheduler only schedules new pods. As clusters grow, nodes become unbalanced. The descheduler runs periodically as a CronJob to evict pods based on policies (e.g. NodeRebalance, LowNodeUtilization, PodLifeTime), allowing the scheduler to place them on better nodes.
2. **[Karpenter](https://karpenter.sh/)**:
   * *What it does*: An open-source, high-performance node provisioning project built for Kubernetes. Unlike the standard Cluster Autoscaler (which works by scaling ASGs/Node Pools), Karpenter talks directly to cloud APIs (AWS EC2, etc.) to launch specialized nodes that fit the exact requirements of Pending Pods in milliseconds.
3. **[Kubernetes Scheduling Gateways (Scheduling Gates)](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-scheduling-readiness/)**:
   * *What it does*: Allows you to declare a Pod as "not ready for scheduling" by applying a gate, preventing the scheduler from wasting cycles trying to schedule it until external controller tasks are finished.

---

## 📖 Official Documentation & Deep Dives

* **[Kubernetes Scheduler Concepts](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)**
* **[Scheduler Configuration API Reference](https://kubernetes.io/docs/reference/config-api/kube-scheduler-config.v1/)**
* **[Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)**
* **[Taints and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)**
* **[Assigning Pods to Nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)**
