# 🛠️ Lab 2: Connecting Clusters via Cilium ClusterMesh

In this lab, you will install Cilium CNI on both `east` and `west` clusters, configure unique cluster IDs, and build a secure eBPF network bridge using the `cilium` CLI.

---

## 🚀 Step 1: Install the Cilium CLI

Download and extract the Cilium command-line helper tool:

```bash
# For Linux/macOS
CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz"
tar xzvf cilium-linux-amd64.tar.gz
sudo mv cilium /usr/local/bin/
rm cilium-linux-amd64.tar.gz
```

Verify the installation:
```bash
cilium version
```

---

## 📦 Step 2: Install Cilium with Unique Cluster IDs

For ClusterMesh to synchronize, each cluster must have a **unique name** and an **integer ID** (between 1 and 255).

1.  **Install Cilium on `east` (ID = 1)**:
    ```bash
    cilium install \
      --context east \
      --set cluster.name=kind-east \
      --set cluster.id=1 \
      --set ipam.operator.clusterPoolIPv4PodCIDRList=10.240.0.0/16
    ```

2.  **Install Cilium on `west` (ID = 2)**:
    ```bash
    cilium install \
      --context west \
      --set cluster.name=kind-west \
      --set cluster.id=2 \
      --set ipam.operator.clusterPoolIPv4PodCIDRList=10.241.0.0/16
    ```

3.  **Verify CNI Status**:
    Wait for pods to stabilize, then run:
    ```bash
    cilium status --context east
    cilium status --context west
    ```

---

## 🔗 Step 3: Enable and Connect ClusterMesh

1.  **Enable ClusterMesh API Server on both clusters**:
    This launches the `clustermesh-apiserver` pods and generates the internal etcd configurations.
    ```bash
    cilium clustermesh enable --context east
    cilium clustermesh enable --context west
    ```

2.  **Connect the Clusters**:
    The CLI will automatically extract the etcd client certificates from `west`, create corresponding Secrets in `east`, and configure the endpoints.
    ```bash
    cilium clustermesh connect --context east --destination-context west
    ```

3.  **Verify ClusterMesh Connectivity Status**:
    ```bash
    cilium clustermesh status --context east
    ```
    *Expected Output*:
    ```
    ✅ Service "clustermesh-apiserver" active
    🔑 ClusterMesh secret found
    ⚡ ClusterMesh connection established:
      - kind-west: OK (1/1 paths healthy)
    ```

---

## 🧪 Step 4: Validate Direct Cross-Cluster Pod Ping

Let's test if a pod in the `east` cluster can ping a pod in the `west` cluster directly via its IP.

1.  **Launch a pod in `west` and capture its IP**:
    ```bash
    kubectl run target-pod --image=alpine --context west -- sleep 3600
    # Wait for running status
    kubectl wait --for=condition=Ready pod/target-pod --context west
    
    WEST_IP=$(kubectl get pod target-pod --context west -o jsonpath='{.status.podIP}')
    echo "West Pod IP: $WEST_IP"
    # Example Output: 10.241.0.45
    ```

2.  **Ping from `east`**:
    Launch a testing pod in the `east` cluster and execute a ping directly to the extracted Western IP:
    ```bash
    kubectl run source-pod --image=alpine --context east -- sleep 3600
    kubectl wait --for=condition=Ready pod/source-pod --context east
    
    kubectl exec source-pod --context east -- ping -c 3 $WEST_IP
    ```
    *Expected Output*:
    ```
    PING 10.241.0.45 (10.241.0.45): 56 data bytes
    64 bytes from 10.241.0.45: seq=0 ttl=62 time=0.884 ms
    64 bytes from 10.241.0.45: seq=1 ttl=62 time=0.912 ms
    64 bytes from 10.241.0.45: seq=2 ttl=62 time=0.890 ms
    
    --- 10.241.0.45 ping statistics ---
    3 packets transmitted, 3 packets received, 0% packet loss
    round-trip min/avg/max = 0.884/0.895/0.912 ms
    ```
    
    > [!TIP]
    > Packet loss should be **0%**. Because of the flat eBPF routing, packets travel directly between docker containers on your machine without NAT gateway hops.
