# 🛠️ Lab 1: Multi-Cluster Environment Setup with KinD

To learn multi-cluster operations without paying cloud provider costs, you will set up two local Kubernetes clusters running concurrently in Docker using **KinD (Kubernetes in Docker)**.

> [!IMPORTANT]
> To connect clusters via a flat network (like Cilium ClusterMesh), their **Pod IP ranges (CIDRs) must not overlap**. This lab configures `kind-east` to use `10.240.0.0/16` and `kind-west` to use `10.241.0.0/16`.

---

## 📋 Prerequisites
*   Docker Desktop or Daemon running.
*   `kind` CLI installed.
*   `kubectl` CLI installed.

---

## 📦 Step 1: Create Cluster Configuration Files

We will declare custom configurations for each cluster to define unique Pod and Service CIDR blocks.

### Create `kind-east.yaml`
Run the following command to write the configuration for the Eastern cluster:

```bash
cat <<EOF > kind-east.yaml
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
networking:
  podSubnet: "10.240.0.0/16"
  serviceSubnet: "10.110.0.0/16"
nodes:
- role: control-plane
- role: worker
EOF
```

### Create `kind-west.yaml`
Run the following command to write the configuration for the Western cluster:

```bash
cat <<EOF > kind-west.yaml
apiVersion: kind.x-k8s.io/v1alpha4
kind: Cluster
networking:
  podSubnet: "10.241.0.0/16"
  serviceSubnet: "10.111.0.0/16"
nodes:
- role: control-plane
- role: worker
EOF
```

---

## 🚀 Step 2: Spin Up the Clusters

1.  **Create the Eastern Cluster**:
    ```bash
    kind create cluster --name kind-east --config kind-east.yaml
    ```
    *Expected Output*:
    ```
    Creating cluster "kind-east" ...
    ✓ Ensuring node image (kindest/node:v1.29.2) 🖼
    ✓ Preparing nodes 📦 📦
    ✓ Writing configuration 📜
    ✓ Starting control-plane 🕹️
    ✓ Installing CNI 🔌
    ✓ Installing StorageClass 💾
    ✓ Joining worker nodes 🤝
    Set kubectl context to "kind-kind-east"
    Cluster "kind-east" successfully created!
    ```

2.  **Create the Western Cluster**:
    ```bash
    kind create cluster --name kind-west --config kind-west.yaml
    ```
    *Expected Output*:
    ```
    Creating cluster "kind-west" ...
    ...
    Set kubectl context to "kind-kind-west"
    Cluster "kind-west" successfully created!
    ```

---

## 🔍 Step 3: Configure Kubeconfig & Context Switching

When you create clusters with KinD, it automatically merges the context configurations into your active `~/.kube/config`.

1.  **List Available Contexts**:
    ```bash
    kubectl config get-contexts
    ```
    *Output*:
    ```
    CURRENT   NAME             CLUSTER          AUTHINFO         NAMESPACE
              kind-kind-east   kind-kind-east   kind-kind-east
    *         kind-kind-west   kind-kind-west   kind-kind-west
    ```

2.  **Rename Contexts for Readability**:
    ```bash
    kubectl config rename-context kind-kind-east east
    kubectl config rename-context kind-kind-west west
    ```

3.  **Test Context Switching**:
    *   Switch to East:
        ```bash
        kubectl config use-context east
        ```
    *   Verify East Pod Subnet:
        ```bash
        kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'
        # Should return: 10.240.0.0/24 (local node partition of 10.240.0.0/16)
        ```
    *   Switch to West:
        ```bash
        kubectl config use-context west
        ```
    *   Verify West Pod Subnet:
        ```bash
        kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'
        # Should return: 10.241.0.0/24 (local node partition of 10.241.0.0/16)
        ```

Now that you have isolated local clusters, you are ready to configure their network connections.
