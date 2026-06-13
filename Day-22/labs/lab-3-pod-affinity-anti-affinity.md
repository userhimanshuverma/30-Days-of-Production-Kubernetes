# 🛠️ Lab 3: Pod Affinity & Anti-Affinity

In this lab, you will configure Pod Anti-Affinity to prevent replicas from scheduling on the same node, and Pod Affinity to co-locate caching services next to API workloads.

---

## 🏃 Step 1: Deploy Web Frontend with Anti-Affinity

We will deploy our web frontend replicas using the manifest [pod-anti-affinity-ha.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-22/manifests/pod-anti-affinity-ha.yaml). This configuration uses `topologyKey: kubernetes.io/hostname` to ensure that no two web pods sit on the same node.

1. Apply the manifest:
   ```bash
   kubectl apply -f manifests/pod-anti-affinity-ha.yaml
   ```

2. Monitor pod placement:
   ```bash
   kubectl get pods -l app=web-frontend -o wide
   ```

3. **Analysis**:
   * If you are running a 3-node cluster and set replicas to 4:
     * 3 pods will schedule successfully (one on each node).
     * The 4th pod will remain `Pending` because scheduling it would violate the host anti-affinity rule.
   * If you are running a single-node cluster (e.g. standard Minikube):
     * Only 1 pod will schedule successfully.
     * The other 3 pods will remain `Pending`.

4. Check the pending pod description:
   ```bash
   # Find a pending pod name
   PENDING_POD=$(kubectl get pods -l app=web-frontend --no-headers | grep Pending | awk '{print $1}' | head -n 1)
   kubectl describe pod $PENDING_POD
   ```
   *Expected Event message*:
   `0/3 nodes are available: 3 node(s) had anti-affinity rules conflict.`

---

## 🏃 Step 2: Deploy Redis Cache Co-located with Web Pods

Now, we will deploy a caching layer using the manifest [pod-affinity-colocation.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-22/manifests/pod-affinity-colocation.yaml). Since this manifest defines a hard pod affinity constraint pointing to `app: web-frontend` with `topologyKey: kubernetes.io/hostname`, each redis pod is forced to land on a node running a frontend pod.

1. Apply the Redis deployment:
   ```bash
   kubectl apply -f manifests/pod-affinity-colocation.yaml
   ```

2. Verify co-location matching:
   ```bash
   kubectl get pods -o wide | grep -E "(web-frontend|cache-redis)" | sort -k 7
   ```

3. **Expected Result**:
   For every node running a `web-frontend` pod, you will find a corresponding `cache-redis` pod. Because redis depends on web-frontend being scheduled, if there are no web-frontend pods on a node, redis won't land there.

4. Clean up resources:
   ```bash
   kubectl delete -f manifests/pod-anti-affinity-ha.yaml
   kubectl delete -f manifests/pod-affinity-colocation.yaml
   ```
