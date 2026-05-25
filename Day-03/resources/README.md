# 📚 Day 3 References & Recommended Reading

To deepen your understanding of Kubernetes architecture and distributed systems theory, explore the following curated resources.

---

## 📖 Official Kubernetes Documentation
* [Kubernetes Components](https://kubernetes.io/docs/concepts/overview/components/) — High-level architecture overview.
* [The Kubernetes API](https://kubernetes.io/docs/concepts/overview/kubernetes-api/) — Understanding API groups, versioning, and schemas.
* [Kubernetes Scheduler](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/) — Filtering, scoring, and customization.
* [Declarative Management using Configuration](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/) — The core design pattern.

---

## 🧠 Distributed Systems Fundamentals
* **Designing Data-Intensive Applications** by Martin Kleppmann (specifically Chapter 8 on Distributed Systems Troubles, and Chapter 9 on Consistency and Consensus).
* **The Raft Consensus Algorithm** ([raft.github.io](https://raft.github.io/)) — Visual explanation of how etcd achieves consensus.
* **Google Site Reliability Engineering Book** ([sre.google/sre-book/table-of-contents/](https://sre.google/sre-book/table-of-contents/)) — Managing state and distributed systems reliability.

---

## ⚡ Technical Deep Dives (Articles & Blogs)
* [A Visual Guide to Kubernetes Networking](https://cizixs.com/2017/03/30/kubernetes-network-model/) — Clear packet tracing guide.
* [Scale testing etcd](https://etcd.io/docs/v3.5/op-guide/performance/) — Performance tuning configurations and disk recommendations.
* [IPVS vs IPTables in Kubernetes](https://kubernetes.io/blog/2018/07/09/ipvs-based-in-cluster-load-balancing-deep-dive/) — Benchmark data showing lookup performance differences at scale.
* [API Priority and Fairness Deep Dive](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/) — Understanding flow schemas and priority levels.

---

## 💻 Code Exploration: GitHub Source Code
For advanced learners, reading the actual Go source code inside the Kubernetes repository is the best way to understand the system:
* [kube-scheduler source code](https://github.com/kubernetes/kubernetes/tree/master/pkg/scheduler) — Follow the scheduling cycle inside `pkg/scheduler/scheduler.go`.
* [kube-apiserver handler chain](https://github.com/kubernetes/kubernetes/tree/master/staging/src/k8s.io/apiserver/pkg/server) — See how authentication and authorization are chained in middleware.
* [kubelet sync loop](https://github.com/kubernetes/kubernetes/tree/master/pkg/kubelet) — Dive into the central pod manager loops inside `pkg/kubelet/kubelet.go`.
