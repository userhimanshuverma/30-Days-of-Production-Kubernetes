# 📚 Day 08 Resources — Recommended Readings

Here is a curated index of documentation, specs, and tools to deepen your knowledge of Kubernetes storage design patterns and operations.

---

## 1. Official Documentation
* [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/): The core concepts reference guide.
* [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/): Parameters and details for cloud providers.
* [Kubernetes StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/): How ordinal index allocation works.

---

## 2. CSI Specification
* [Container Storage Interface (CSI) Spec](https://github.com/container-storage-interface/spec): Official spec defining gRPC interfaces (`CreateVolume`, `NodePublish`, etc.) used by drivers.
* [Kubernetes CSI Developer Guide](https://kubernetes-csi.github.io/docs/): Technical documentation on how CSI drivers and K8s sidecars interact.

---

## 3. Production Drivers (Code & Manuals)
* [AWS EBS CSI Driver GitHub Repository](https://github.com/kubernetes-sigs/aws-ebs-csi-driver): Official AWS block storage driver.
* [GCP Persistent Disk CSI Driver](https://github.com/kubernetes-sigs/gcp-compute-persistent-disk-csi-driver): Official Google Cloud block storage driver.
* [Ceph CSI Driver Documentation](https://github.com/ceph/ceph-csi): High performance distributed storage for on-premise deployments.

---

## 4. Benchmarking & Testing Tools
* [fio (Flexible I/O Tester)](https://github.com/axboe/fio): Standard benchmarking utility for raw disk block performance.
* [Kubestr](https://github.com/kastenhq/kubestr): A CLI tool to discover and run storage performance benchmarks on a running K8s cluster.
* [Velero Backup & Restore](https://velero.io/): Production tool to automate snapshot-based backups.
