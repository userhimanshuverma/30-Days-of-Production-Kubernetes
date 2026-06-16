# 🛠️ Lab 5: Disaster Recovery & Region Failover Testing

In this lab, you will perform a destructive test: you will cut the virtual network link to the `west` cluster, monitor how the GSLB and routing systems react, and verify the recovery when the link is restored.

---

## 🚨 Step 1: Simulate the Regional Outage

To simulate a complete region blackout, we will disconnect the `kind-west` nodes from the shared Docker network bridge (`kind`).

1.  **Find the Container Names**:
    ```bash
    docker ps --filter "name=kind-west"
    ```
    *Output*:
    ```
    CONTAINER ID   IMAGE                  NAMES
    a4f32c918a3d   kindest/node:v1.29.2   kind-west-control-plane
    e816a1b24d77   kindest/node:v1.29.2   kind-west-worker
    ```

2.  **Disconnect the Nodes from the Bridge Network**:
    This instantly prevents any network packet transfers to or from the `kind-west` cluster.
    ```bash
    docker network disconnect kind kind-west-control-plane
    docker network disconnect kind kind-west-worker
    ```

---

## 🔍 Step 2: Observe System Degradation

1.  **Check Context Status from `east` (Hub)**:
    Since the network link is cut, the Hub cluster's API client will time out trying to query the worker:
    ```bash
    kubectl --context east get nodes
    # Works normally (returns east nodes)
    
    kubectl --context west get nodes
    # Should block and fail with connection timeout
    ```

2.  **Inspect Karmada Cluster Registry Status**:
    Switch your context back to Karmada Hub:
    ```bash
    export KUBECONFIG=~/.kube/karmada.config
    karmadactl get clusters
    ```
    *Expected Output*:
    ```
    NAME        VERSION   MODE   READY   STATUS    AGE
    kind-east   v1.29.2   Push   True    Healthy   15m
    kind-west   v1.29.2   Push   False   Offline   14m
    ```
    > [!IMPORTANT]
    > Karmada has marked `kind-west` as **Offline**. The scheduler will trigger eviction events for all workloads managed by propagation policies.

3.  **Check Eviction Events**:
    ```bash
    kubectl get events -n production --sort-by='.metadata.creationTimestamp'
    ```
    You will see Karmada scheduling controller withdrawing deployment tasks from the offline cluster and attempting to shift all remaining replicas to the healthy `kind-east` cluster to maintain application capacity.

---

## 🔌 Step 3: Verify GSLB Health Check Failover

1.  **Perform DNS Resolution Test**:
    Query the DNS server for European users (which previously resolved to the Western cluster `198.51.100.20`):
    ```bash
    dig @localhost -p 1053 api.global.company.com +subnet=194.0.0.0/24
    ```
    *Expected Output*:
    ```
    ;; ANSWER SECTION:
    api.global.company.com.  30  IN  A  192.0.2.10
    ```
    The GSLB successfully identified that `kind-west` is down, withdrawing its IP from the pool and redirecting EU users to the US East endpoint (`192.0.2.10`).

---

## 💚 Step 4: Restore the Network Link & Verify Recovery

1.  **Reconnect the Nodes**:
    ```bash
    docker network connect kind kind-west-control-plane
    docker network connect kind kind-west-worker
    ```

2.  **Monitor Cluster Re-Join**:
    Wait ~30 seconds for the nodes to synchronize, then verify cluster status:
    ```bash
    export KUBECONFIG=~/.kube/karmada.config
    karmadactl get clusters
    ```
    *Output*:
    ```
    NAME        VERSION   MODE   READY   STATUS    AGE
    kind-east   v1.29.2   Push   True    Healthy   17m
    kind-west   v1.29.2   Push   True    Healthy   16m
    ```

3.  **Verify Workload Re-balance**:
    Once the cluster returns to a healthy status, Karmada synchronizes the state and redistributes the replicas back to the 60/40 weighted layout:
    ```bash
    export KUBECONFIG=~/.kube/config
    kubectl get pods -n production --context west
    # Replicas are scaling back up to 4 pods
    ```
