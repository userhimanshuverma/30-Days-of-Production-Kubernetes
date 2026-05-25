# Lab 6: Analyzing kubelet Operations

The `kubelet` is the node agent that communicates with the container runtime. In this lab, you will explore the kubelet configuration file, read its logs directly from the node's systemd journal, and deploy a **Static Pod** that bypasses the control plane entirely.

---

## 🏃 Step 1: Exec into a Worker Node
We will inspect the kubelet from the perspective of a worker node. Exec into your worker node container:
```bash
docker exec -it k8s-internals-worker bash
```

---

## 🏃 Step 2: Read kubelet Configuration
The kubelet is configured via a YAML file, typically located at `/var/lib/kubelet/config.yaml`. Let's inspect this configuration:
```bash
cat /var/lib/kubelet/config.yaml
```

Look for these key production parameters in the output:
* `staticPodPath`: Defines the directory where the Kubelet scans for static pod files. Typically `/etc/kubernetes/manifests`.
* `clusterDNS`: The IP address of the CoreDNS server (usually `10.96.0.10`). The Kubelet configures this IP in every container's `/etc/resolv.conf`.
* `evictionHard`: Defines the resource thresholds (like memory available < 100Mi) that trigger the Kubelet to evict pods to protect the host OS from out-of-memory lockups.

---

## 🏃 Step 3: Stream kubelet System Logs
Because the Kubelet runs as a native system service, its log output is sent to the system journal.
Stream the logs to view active operations:
```bash
journalctl -u kubelet -n 50 -f
```

You should see logs indicating regular node status reports and status updates:
```
May 25 14:25:10 k8s-internals-worker kubelet[312]: I0525 14:25:10.123512  312 status_manager.go:610] "Patching pod status" pod="default/nginx"
May 25 14:25:12 k8s-internals-worker kubelet[312]: I0525 14:25:12.355122  312 kubelet.go:2104] "SyncLoop UPDATE" source="api"
```

Type `Ctrl+C` to exit the logs.

---

## 🏃 Step 4: Create a Static Pod
Now, let's deploy a Static Pod. A static pod is read directly from a host folder and run by the Kubelet, bypassing the Scheduler.

First, check if the static pod directory exists. If not, create it:
```bash
mkdir -p /etc/kubernetes/manifests
```

Write the following manifest directly into the static pod path:
```bash
cat <<EOF > /etc/kubernetes/manifests/static-nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-nginx
spec:
  containers:
  - name: web
    image: nginx:alpine
EOF
```

Within a few seconds, the Kubelet's file watcher will notice the file, contact the local containerd daemon, and launch the pod.
List the running containers on the node directly using `crictl` (the CLI for CRI-compatible runtimes):
```bash
crictl ps | grep static-nginx
```

**Expected Output:**
```
c129f120199d0    nginx:alpine    2 seconds ago    Running    web    ...
```

Now, exit the worker node container:
```bash
exit
```

---

## 🏃 Step 5: Verify the Mirror Pod in the Control Plane
On your host terminal, query the pods list:
```bash
kubectl get pods -o wide
```

**Expected Output:**
```
NAME                                       READY   STATUS    RESTARTS   AGE    IP            NODE
static-nginx-k8s-internals-worker          1/1     Running   0          45s    10.244.1.12   k8s-internals-worker
```

### Key Architectural Concepts to Observe:
1. **Mirror Pod:** The pod is appended with the node name (`-k8s-internals-worker`). The API Server creates a read-only "mirror pod" so operators can monitor the static pod using standard kubectl commands.
2. **Immutable via API:** Try to delete the pod via `kubectl`:
   ```bash
   kubectl delete pod static-nginx-k8s-internals-worker
   ```
   Now run `kubectl get pods` again. The pod is immediately running. Why? The API Server cannot delete static pods. The Kubelet is the authority, and as long as the file `/etc/kubernetes/manifests/static-nginx.yaml` exists on the node's disk, it will ensure the containers are running.
3. **To clean it up:** You must exec back into the worker node container and delete the manifest:
   ```bash
   docker exec -it k8s-internals-worker rm /etc/kubernetes/manifests/static-nginx.yaml
   ```
   Check `kubectl get pods` on the host, and you will see the pod has gracefully disappeared.
