# 🔗 Node & Pod Affinity / Anti-Affinity Reference Guide

Affinity and anti-affinity rules give you granular control over where your Pods land by using labels on nodes and existing Pods.

---

## 🎯 1. Node Selector vs. Node Affinity

In early Kubernetes versions, `nodeSelector` was the only way to constrain Pods to specific nodes. Node Affinity extends this with richer expressions and soft rules.

| Feature | `nodeSelector` | Node Affinity |
|---|---|---|
| **Constraint Type** | Hard only (Must match) | Hard (`required...`) & Soft (`preferred...`) |
| **Operators** | Exact match (`key: value`) | `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt` |
| **Custom Scoring** | No | Yes (Weights assigned to soft preferences) |
| **Execution Phase** | Ignored during execution | Ignored during execution (though future versions may evict) |

### Node Affinity Structure

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: topology.kubernetes.io/zone
            operator: In
            values: ["us-east-1a", "us-east-1b"]
```

---

## 👥 2. Pod Affinity & Anti-Affinity

While Node Affinity matches Node labels, **Pod Affinity** and **Pod Anti-Affinity** match the labels of Pods already running on those nodes.

### The Critical Role of `topologyKey`

You must specify a `topologyKey` with Pod affinity/anti-affinity rules. It tells Kubernetes what boundary defines "co-location" or "separation".

* **`kubernetes.io/hostname`**: Physical machine boundary. If a pod is anti-affine with this topology key, they will never sit on the same physical VM.
* **`topology.kubernetes.io/zone`**: Availability Zone (AZ) boundary. If a pod is anti-affine with this topology key, they will never sit in the same availability zone.
* **`topology.kubernetes.io/region`**: Cloud region boundary.

### High Availability Pattern: Anti-Affinity

To ensure your application survives an AZ or VM outage, use anti-affinity:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values: ["web-frontend"]
      topologyKey: kubernetes.io/hostname
```

### Co-location Pattern: Affinity

To minimize network latency between a front-end container and a cache, use pod affinity:

```yaml
affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app
          operator: In
          values: ["web-frontend"]
      topologyKey: kubernetes.io/hostname
```
