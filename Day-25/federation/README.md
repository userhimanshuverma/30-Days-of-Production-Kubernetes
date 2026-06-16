# 🤝 Cluster Federation: Karmada vs. KubeFed vs. OCM

This guide examines the history, architectural differences, and operational designs of the three major Kubernetes cluster federation technologies.

---

## ⚖️ 1. Evolution and Comparison Table

| Feature | KubeFed (v2) [Deprecated] | Karmada [Modern Standard] | Open Cluster Management (OCM) |
| :--- | :--- | :--- | :--- |
| **API Compatibility** | Requires wrapping standard APIs in Federated CRDs (e.g., `FederatedDeployment`). | **100% Native Kubernetes APIs** (Standard Deployment, Service, ConfigMap). | Native APIs wrapped in `ManifestWork` wrapper objects. |
| **Architecture** | Direct push model from a central controller. | Hub-and-Spoke supporting both **Push** and **Pull** agent models. | Agent-driven Hub-and-Spoke model. |
| **Override System** | Complex JSON patching in federated manifests. | Declarative **OverridePolicies** matching label selectors. | Parameterized templates and localization parameters. |
| **Use Case** | Early multi-cluster attempts (2018-2020). | Workload-centric scheduling, global resilience, app bursting. | Governance, compliance, policy auditing, and fleet configuration. |

---

## 🚀 2. Karmada Under the Hood

Karmada (Kubernetes Armada) is a CNCF incubating project originally designed by Huawei and community members to solve the main usability issues of KubeFed.

### A. The Direct API Compatibility Break
In KubeFed, developers had to rewrite all their Helm charts. A standard `Deployment` resource had to be translated into:
```yaml
apiVersion: types.kubefed.io/v1beta1
kind: FederatedDeployment
metadata:
  name: sample-app
spec:
  template: ... # Standard Deployment Spec here
  placement: ... # Where to deploy
  overrides: ... # Local overrides
```
This broke standard CI/CD pipelines, IDE plugins, and third-party tools.

Karmada solved this by keeping the standard APIs. The user runs `kubectl apply -f deployment.yaml` directly on the **Karmada Hub control plane**. Karmada intercepts it, watches for a `PropagationPolicy` that matches it, and replicates it behind the scenes.

### B. Push vs. Pull Execution Modes
1.  **Push Mode**: The Karmada Hub controller communicates directly with the API servers of the spoke worker clusters. It pushes changes directly.
    *   *Requirement*: The Hub must have network routing to, and admin credentials for, every worker cluster API server.
2.  **Pull Mode**: An agent (`karmada-agent`) runs inside the spoke worker cluster. It connects out to the Karmada Hub API server via a secure reverse tunnel, pulls scheduled work tasks, and applies them locally.
    *   *Requirement*: Spoke clusters only need outbound network access to the Hub. No admin credentials are stored on the Hub. Ideal for security-sensitive or private data centers.

---

## 🛡️ 3. Open Cluster Management (OCM) Under the Hood

OCM (originally initiated by Red Hat) takes a cluster-centric, rather than workload-centric, approach to fleet management.

### Key Concepts in OCM:
*   **ManagedCluster**: The registration object on the hub that defines a worker cluster's state, IP addresses, and metadata.
*   **Placement**: An engine that selects a set of `ManagedClusters` based on labels or capacity.
*   **ManifestWork**: An API object on the Hub that contains a list of raw Kubernetes manifests to be applied on the managed cluster by its local agent (`klusterlet`).

OCM excels at enterprise governance. For example, you can write a policy: *"Every cluster labeled `compliance=gdpr` must run a specific security logging agent daemonset."* If an operator deletes the daemonset locally on a worker cluster, the OCM agent automatically re-applies it (drift correction).

---

## 🛠️ 4. Concrete Karmada Manifest Example

Here is how you define a federated layout using native deployments and Karmada control manifests:

### The Resource Template (Standard Deployment)
```yaml
# Applied directly to Karmada Hub API server
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-processor
  labels:
    app: payment-processor
spec:
  replicas: 10
  selector:
    matchLabels:
      app: payment-processor
  template:
    metadata:
      labels:
        app: payment-processor
    spec:
      containers:
      - name: processor
        image: payment-system:v2.1.0
        env:
        - name: DATABASE_HOST
          value: "db-us.company.com"
```

### The Propagation Policy (Defines Scheduling Logic)
```yaml
# Applied to Karmada Hub
apiVersion: policy.karmada.io/v1alpha1
kind: PropagationPolicy
metadata:
  name: split-payments
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      name: payment-processor
  association: true
  placement:
    clusterAffinity:
      clusterNames:
        - prod-us-east
        - prod-eu-west
    replicaScheduling:
      replicaDivisionPreference: Weighted
      replicaSchedulingType: Divided
      weightPreference:
        staticWeightList:
          - targetCluster:
              clusterName: prod-us-east
            weight: 7
          - targetCluster:
              clusterName: prod-eu-west
            weight: 3
```
*   **Result**: Karmada automatically calculates: 7 replicas are scheduled to `prod-us-east`, and 3 replicas are scheduled to `prod-eu-west`.

### The Override Policy (Customizes Values per Cluster)
```yaml
apiVersion: policy.karmada.io/v1alpha1
kind: OverridePolicy
metadata:
  name: customize-eu-db
spec:
  resourceSelectors:
    - apiVersion: apps/v1
      kind: Deployment
      name: payment-processor
  targetCluster:
    clusterNames:
      - prod-eu-west
  overriders:
    plaintext:
      - path: /spec/template/spec/containers/0/env/0/value
        operator: replace
        value: "db-eu.company.eu"
```
*   **Result**: Before applying the deployment manifest to `prod-eu-west`, Karmada automatically patches the environment variable block to point to the local European database endpoint.
