# Lab 5: Inspecting etcd Objects

All Kubernetes configuration and state is persisted inside `etcd`. In this lab, you will bypass the API Server entirely, execute queries directly against the `etcd` database, and inspect how resource objects are stored on disk.

---

## 🏃 Step 1: Exec into the Control Plane Node
In a standard `kind` or `kubeadm` cluster, etcd runs locally on the control plane node. Let's enter the control-plane container:
```bash
docker exec -it k8s-internals-control-plane bash
```

Once inside the shell, verify that the `etcdctl` utility is available. In Kind nodes, it is usually installed:
```bash
etcdctl --version
```
*If etcdctl is not in the path, we can locate it or run it via the etcd container itself. Let's export the command alias to simplify our queries:*
```bash
alias local-etcdctl="etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key"
```

---

## 🏃 Step 2: Query All Key Prefixes in the Database
Kubernetes prefixes all its keys with `/registry/`. Let's list the top-level directories (keys-only format) in the database to see how etcd structures its data:
```bash
local-etcdctl get "" --prefix --keys-only | cut -d'/' -f1-4 | sort -u
```

**Expected Output:**
```
/registry/apiextensions.k8s.io/customresourcedefinitions
/registry/apiregistration.k8s.io/apiservices
/registry/apps/daemonsets
/registry/apps/deployments
/registry/apps/replicasets
/registry/apps/statefulsets
/registry/configmaps
/registry/events
/registry/namespaces
/registry/pods
/registry/secrets
/registry/services/endpoints
/registry/services/specs
```

Notice how the folder names map directly to the API Groups (`apps/deployments`, `configmaps`, `pods`).

---

## 🏃 Step 3: Write a Resource and Read the Raw Key
Let's see what a Pod object actually looks like inside etcd.

Open another terminal window on your host (keep your docker exec session alive in the first terminal) and run a temporary pod:
```bash
kubectl run etcd-demo-pod --image=nginx:alpine
```

Now, return to the first terminal (inside the control-plane node) and retrieve the specific key for this pod:
```bash
local-etcdctl get /registry/pods/default/etcd-demo-pod
```

**Expected Output:**
You will see a large stream of output containing some binary characters mixed with human-readable text. It should look somewhat like this:
```
/registry/pods/default/etcd-demo-pod
k8s

v1Pod
etcd-demo-poddefault"*$a61e7b2f-7a42-45e3-982c-15a0c329b31d2Z
runetcd-demo-pod
                  nginx:alpineJ
```

### Why is the output mixed with gibberish?
* **Protobuf Serialization:** The API Server does not write JSON or YAML to etcd. It serializes Go objects into **Protocol Buffers (protobuf)** binary format before writing them.
* **Why Protobuf?**
  1. **Performance:** Serializing and deserializing protobuf is up to 10x faster than JSON parsing.
  2. **Storage Efficiency:** Protobuf is a compressed binary representation, significantly reducing the disk footprint inside etcd.

Let's clean up our demo pod and exit the node.

On your host terminal:
```bash
kubectl delete pod etcd-demo-pod
```

On your exec session:
```bash
exit
```
