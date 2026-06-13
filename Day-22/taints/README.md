# 🚫 Taints & Tolerations Reference Guide

Taints and tolerations work together to ensure that Pods are not scheduled onto inappropriate nodes. While affinity rules *attract* Pods to nodes, taints do the opposite — they allow a node to *repel* a set of Pods.

---

## 🏗️ The Taint Mechanism

A taint is applied to a node and consists of a `key`, `value`, and `effect`:

```bash
kubectl taint nodes worker-gpu-01 hardware=gpu:NoSchedule
```

A Pod will only schedule onto this node if it has a matching toleration in its PodSpec:

```yaml
spec:
  tolerations:
  - key: "hardware"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
```

---

## ⚡ The Three Taint Effects

| Effect | Scheduling Action | Execution Action | Use Case |
|---|---|---|---|
| **`NoSchedule`** | Hard block. Pods without toleration cannot be scheduled. | Existing pods on the node are unaffected. | Dedicated node pools (e.g., GPU, billing compute). |
| **`PreferNoSchedule`** | Soft block. Scheduler tries to avoid the node, but can use it as a last resort. | Existing pods are unaffected. | Graceful node draining or cluster defragmentation. |
| **`NoExecute`** | Hard block. Un-tolerated pods cannot be scheduled. | Existing pods without toleration are **evicted immediately**. | Node failures (e.g., NetworkUnavailable, DiskPressure). |

---

## 🕰️ Dynamic Eviction with `NoExecute`

When a node experiences a problem, Kubernetes automatically adds a `NoExecute` taint to it. For example, if a node becomes unreachable, the node controller adds:

* `node.kubernetes.io/unreachable:NoExecute`
* `node.kubernetes.io/not-ready:NoExecute`

If a Pod does not tolerate these, it is evicted. However, you can add a **toleration delay** using `tolerationSeconds` so that temporary hiccups do not trigger a cascading eviction:

```yaml
spec:
  tolerations:
  - key: "node.kubernetes.io/unreachable"
    operator: "Exists"
    effect: "NoExecute"
    tolerationSeconds: 300 # Wait 5 minutes before evicting
```

---

## 🧠 TaintManager Internal Mechanics

The **TaintManager** is a controller inside the `kube-controller-manager` that constantly monitors node events. When a `NoExecute` taint is added to a node, the TaintManager:

1. Lists all Pods running on that node.
2. Filters out Pods that have a matching toleration (with no `tolerationSeconds` limit).
3. Schedules evictions for Pods that tolerate the taint for a limited time (`tolerationSeconds`).
4. Immediately deletes Pods that do not tolerate the taint.
