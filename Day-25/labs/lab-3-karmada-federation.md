# 🛠️ Lab 3: Workload Federation with Karmada

In this lab, you will configure a central **Karmada Hub** control plane, register `kind-east` and `kind-west` as worker clusters, and deploy a federated web application with automatic replica splitting and cluster-specific configurations.

---

## 🚀 Step 1: Install the Karmada Command CLI

Install the `karmadactl` binary to manage the cluster join sequences:

```bash
curl -LO "https://github.com/karmada-io/karmada/releases/download/v1.9.0/karmadactl-linux-amd64.tgz"
tar -zxf karmadactl-linux-amd64.tgz
sudo mv karmadactl /usr/local/bin/
rm karmadactl-linux-amd64.tgz
```

---

## 🏗️ Step 2: Initialize Karmada Control Plane

We will host the Karmada control plane inside our `east` cluster (acting as the Hub).

1.  **Run Karmada Installation**:
    ```bash
    karmadactl init --context east
    ```
    This creates a dedicated namespace `karmada-system` containing a nested, minimal API server, controller-manager, scheduler, and an etcd cluster specifically dedicated to federation logic.
    
    *Expected Output*:
    ```
    Karmada is installed successfully!
    To start using karmada, run:
      export KUBECONFIG=~/.kube/karmada.config
    ```

2.  **Verify Karmada Core Services**:
    ```bash
    kubectl get pods -n karmada-system --context east
    ```

---

## 🤝 Step 3: Register Spoke Clusters

To manage the clusters, Karmada must join them to its host registry.

1.  **Register `kind-east` (as a local worker spoke)**:
    ```bash
    karmadactl --kubeconfig ~/.kube/karmada.config join kind-east \
      --cluster-kubeconfig ~/.kube/config \
      --cluster-context east
    ```

2.  **Register `kind-west` (as a remote worker spoke)**:
    ```bash
    karmadactl --kubeconfig ~/.kube/karmada.config join kind-west \
      --cluster-kubeconfig ~/.kube/config \
      --cluster-context west
    ```

3.  **Verify Registered Fleet**:
    ```bash
    karmadactl --kubeconfig ~/.kube/karmada.config get clusters
    ```
    *Output*:
    ```
    NAME        VERSION   MODE   READY   AGE
    kind-east   v1.29.2   Push   True    45s
    kind-west   v1.29.2   Push   True    32s
    ```

---

## 📦 Step 4: Deploy Federated Workload

Now we will switch our active kubeconfig targeting context to the **Karmada API Server** rather than the individual cluster.

1.  **Switch active config to Karmada**:
    ```bash
    export KUBECONFIG=~/.kube/karmada.config
    ```

2.  **Create Namespace in Karmada Control Plane**:
    ```bash
    kubectl create namespace production
    ```

3.  **Apply Workload Templates, Overrides and Propagation Policies**:
    We will apply the manifest file we wrote earlier:
    ```bash
    kubectl apply -f ../manifests/karmada-federated-deployment.yaml
    ```

---

## 🔍 Step 5: Verify Replica Splitting & Overrides

Karmada evaluates the scheduling policy: **Replicas = 10; 60% weight to `kind-east` and 40% weight to `kind-west`.**

1.  **Query deployment status from Karmada Hub**:
    ```bash
    kubectl get deployment dynamic-web-frontend -n production
    ```
    *Output*:
    ```
    NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
    dynamic-web-frontend    10/10   10           10          1m
    ```

2.  **Switch back to local cluster contexts to inspect physical deployments**:
    ```bash
    export KUBECONFIG=~/.kube/config
    ```

3.  **Verify replicas in `kind-east` (Expected: 6 pods)**:
    ```bash
    kubectl get pods -n production --context east
    # Should list 6 running pods
    ```

4.  **Verify replicas in `kind-west` (Expected: 4 pods)**:
    ```bash
    kubectl get pods -n production --context west
    # Should list 4 running pods
    ```

5.  **Inspect Env Overrides**:
    *   Query environment variables in `east` pod:
        ```bash
        EAST_POD=$(kubectl get pods -n production --context east -o jsonpath='{.items[0].metadata.name}')
        kubectl exec -n production --context east $EAST_POD -- env | grep -E "REGION_NAME|DATABASE_URL"
        ```
        *Output*:
        ```
        REGION_NAME=us-east-1
        DATABASE_URL=jdbc:postgresql://db-east.internal.company.com/prod
        ```
    *   Query environment variables in `west` pod:
        ```bash
        WEST_POD=$(kubectl get pods -n production --context west -o jsonpath='{.items[0].metadata.name}')
        kubectl exec -n production --context west $WEST_POD -- env | grep -E "REGION_NAME|DATABASE_URL"
        ```
        *Output*:
        ```
        REGION_NAME=us-west-2
        DATABASE_URL=jdbc:postgresql://db-west.internal.company.com/prod
        ```

Excellent! You have successfully deployed a globally federated, region-customized app.
