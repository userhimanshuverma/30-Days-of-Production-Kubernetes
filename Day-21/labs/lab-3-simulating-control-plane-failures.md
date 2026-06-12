# 🛠️ Lab 3: Simulating Control Plane Failures

In this lab, you will explore the resiliency of a multi-node control plane. You will query the etcd Raft consensus group, crash a control plane node to verify automatic routing failover, simulate a loss of quorum by crashing a second node, and observe cluster self-healing.

---

## 🏃 Step 1: Inspect the etcd Cluster Members

First, let's identify the members of our etcd cluster.

1. Find the name of one of your control plane nodes:
   ```bash
   kubectl get nodes -l node-role.kubernetes.io/control-plane
   # Nodes: k8s-production-ops-control-plane, k8s-production-ops-control-plane2, k8s-production-ops-control-plane3
   ```

2. Exec into the first control plane node to run `etcdctl`:
   ```bash
   docker exec -it k8s-production-ops-control-plane bash
   ```

3. Run the member list command:
   ```bash
   ETCDCTL_API=3 etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     member list -w table
   ```

4. **Expected Output**:
   ```text
   +------------------+---------+--------------------------------------+--------------------------+--------------------------+------------+
   |        ID        | STATUS  |                 NAME                 |        PEER URLS         |       CLIENT URLS        | IS LEARNER |
   +------------------+---------+--------------------------------------+--------------------------+--------------------------+------------+
   | 2c7da197825d4821 | started | k8s-production-ops-control-plane     | https://172.18.0.7:2380  | https://172.18.0.7:2379  |      false |
   | 8e91cb349a74b10b | started | k8s-production-ops-control-plane2    | https://172.18.0.3:2380  | https://172.18.0.3:2379  |      false |
   | a481efda7d52c803 | started | k8s-production-ops-control-plane3    | https://172.18.0.2:2380  | https://172.18.0.2:2379  |      false |
   +------------------+---------+--------------------------------------+--------------------------+--------------------------+------------+
   ```
   *Note that all 3 members are active. Our cluster size N is 3. Quorum is 2.*

5. Exit the container:
   ```bash
   exit
   ```

---

## 🏃 Step 2: Crash 1 of 3 Control Plane Nodes

We will simulate a physical hardware crash or hypervisor failure on the second control plane node (`k8s-production-ops-control-plane2`).

1. Stop the Docker container representing control-plane-2:
   ```bash
   docker stop k8s-production-ops-control-plane2
   ```

2. Immediately test your ability to read cluster resources from your host:
   ```bash
   kubectl get nodes
   ```
   *The command should execute immediately and successfully! The request is routed via the local kube-apiserver load balancer to control-plane-1 or control-plane-3.*

3. Check node statuses:
   ```bash
   kubectl get nodes
   ```
   *Within 40 seconds, `k8s-production-ops-control-plane2` will transition to `NotReady` status, but the surviving control plane nodes remain healthy.*

4. Exec into `k8s-production-ops-control-plane` and check etcd member health:
   ```bash
   docker exec -it k8s-production-ops-control-plane etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     endpoint health --write-out=table
   ```
   *You will see that endpoint 2 returns a connection error, but endpoint 1 and 3 are healthy. The database remains fully writable.*

---

## 🏃 Step 3: Simulate Loss of Quorum (Crash a Second Node)

In a 3-node cluster, we can tolerate exactly 1 failure. Let's crash the third node (`k8s-production-ops-control-plane3`) to see what happens when quorum is lost.

1. Stop the third control plane container:
   ```bash
   docker stop k8s-production-ops-control-plane3
   ```

2. Now try to query the cluster state:
   ```bash
   kubectl get pods -n kube-system
   ```
   *The command will hang indefinitely or return a connection refused error. Because etcd has only 1 active node left out of 3, it cannot establish Raft quorum. The remaining node rejects all requests.*

---

## 🏃 Step 4: Observe Self-Healing on Recovery

Let's revive our crashed nodes and observe how the cluster recovers.

1. Start the containers back up:
   ```bash
   docker start k8s-production-ops-control-plane2
   docker start k8s-production-ops-control-plane3
   ```

2. Wait 20 seconds, then query the cluster:
   ```bash
   kubectl get nodes
   ```
   *The command executes successfully! Once a majority of nodes (2 out of 3) are active, etcd establishes a leader, syncs state, and re-activates the API server.*

3. Verify that all 3 nodes return to `Ready` state:
   ```bash
   kubectl get nodes
   ```
