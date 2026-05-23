# 📚 Day 1: Reference Materials & Deep Dives

To expand your engineering understanding of containerization and orchestration, review the following primary resources.

---

## 🔬 Systems Architecture & Whitepapers

1. **Large-Scale Cluster Management at Google with Borg:**
   * *Description:* The foundational research paper that inspired Kubernetes. Google explains how they managed millions of containers across thousands of clusters using "Borg".
   * *URL:* [Google Borg Whitepaper (PDF)](https://research.google/pubs/large-scale-cluster-management-at-google-with-borg/)

2. **The Open Container Initiative (OCI) Specifications:**
   * *Description:* Read the official specifications defining how container runtime bundles (`runtime-spec`) and container images (`image-spec`) must be structured.
   * *URL:* [Open Container Initiative Github](https://github.com/opencontainers)

---

## 🐧 Linux Kernel Foundations

1. **Linux Namespaces Deep Dive:**
   * *Description:* Man-pages documenting the kernel namespaces (`pid`, `net`, `mnt`, `ipc`, `uts`, `user`) that form the boundary of containers.
   * *URL:* [Linux Namespaces Man Page](https://man7.org/linux/man-pages/man7/namespaces.7.html)

2. **Control Groups (cgroups):**
   * *Description:* Official kernel documentation outlining cgroups v1 and cgroups v2 resource restriction behaviors.
   * *URL:* [Kernel Cgroups Documentation](https://www.kernel.org/doc/Documentation/cgroup-v1/cgroups.txt)

---

## ☸️ Kubernetes Core Concepts

1. **Kubernetes Architecture Internals:**
   * *Description:* Understand the design of control plane components and node agents.
   * *URL:* [K8s Concept Components](https://kubernetes.io/docs/concepts/overview/components/)

2. **Declarative Management of Kubernetes Objects:**
   * *Description:* A comparison of Imperative Commands vs. Imperative Object Configuration vs. Declarative Object Configuration.
   * *URL:* [K8s Object Management](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/)
