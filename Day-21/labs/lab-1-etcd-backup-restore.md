# 🛠️ Lab 1: etcd Backup and Restore

In this lab, you will connect to a Kind control plane node, execute a manual etcd snapshot, write temporary state to the cluster, perform a database restore, and verify that the database has rolled back to the backup state.

---

## 🏃 Step 1: Connect to the Control Plane Container

Since Kind runs nodes as Docker containers, we can shell directly into the master node container:

```bash
docker ps | grep control-plane
# Note the name of one of the control-plane containers, e.g. "k8s-production-ops-control-plane"

docker exec -it k8s-production-ops-control-plane bash
```

Inside the container, verify that `etcdctl` is available. (In Kind, `etcdctl` is pre-installed or can be executed via the `etcd` container image):
```bash
etcdctl --version
```

---

## 🏃 Step 2: Take a Snapshot of the Database

We will run a snapshot command using the local certificates mounted inside the control plane.

1. Create a backup folder on the control-plane host:
   ```bash
   mkdir -p /var/backups/etcd
   ```

2. Run `etcdctl snapshot save`:
   ```bash
   ETCDCTL_API=3 etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key \
     snapshot save /var/backups/etcd/pre-disaster.db
   ```

3. **Expected Output**:
   ```text
   Snapshot saved at /var/backups/etcd/pre-disaster.db
   ```

4. Verify the snapshot size and hash:
   ```bash
   ETCDCTL_API=3 etcdctl --write-out=table snapshot status /var/backups/etcd/pre-disaster.db
   ```

---

## 🏃 Step 3: Simulate a Disaster (Create State to Lose)

Exit the master container back to your local terminal, then create a mock namespace and deployment representing "new data" that will be lost in the restore:

```bash
# Return to your workstation terminal
exit

# Create a resource to test the rollback
kubectl create namespace disaster-zone
kubectl create deployment web-server --image=nginx -n disaster-zone

# Verify the deployment is running
kubectl get pods -n disaster-zone
```

---

## 🏃 Step 4: Perform the Restore Operation

Now, we will roll back the cluster state to `/var/backups/etcd/pre-disaster.db`. Since we took the backup *before* creating the `disaster-zone` namespace, a successful restore will erase this namespace.

1. Shell back into the control-plane container:
   ```bash
   docker exec -it k8s-production-ops-control-plane bash
   ```

2. Stop the static pods. Move `kube-apiserver.yaml` and `etcd.yaml` out of `/etc/kubernetes/manifests`:
   ```bash
   mkdir -p /tmp/manifest-backup
   mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/manifest-backup/
   mv /etc/kubernetes/manifests/etcd.yaml /tmp/manifest-backup/
   ```

3. Wait 10 seconds and verify that the containers are stopped:
   ```bash
   crictl ps | grep -E "(etcd|kube-apiserver)"
   # This should return nothing
   ```

4. Delete the existing database folder:
   ```bash
   rm -rf /var/lib/etcd
   ```

5. Run `etcdctl snapshot restore`:
   ```bash
   ETCDCTL_API=3 etcdctl snapshot restore /var/backups/etcd/pre-disaster.db \
     --name=k8s-production-ops-control-plane \
     --data-dir=/var/lib/etcd \
     --initial-cluster=k8s-production-ops-control-plane=https://127.0.0.1:2380 \
     --initial-cluster-token=etcd-bootstrap-token \
     --initial-advertise-peer-urls=https://127.0.0.1:2380
   ```

6. Verify that permissions are correct:
   ```bash
   chown -R root:root /var/lib/etcd
   ```

7. Re-enable the static pods by moving the manifests back:
   ```bash
   mv /tmp/manifest-backup/* /etc/kubernetes/manifests/
   ```

8. Exit the container:
   ```bash
   exit
   ```

---

## 🏃 Step 5: Verify the Rollback

On your workstation terminal, wait for the API server to start responding again (this may take up to a minute as the kubelet restarts the static pods):

```bash
# Monitor the API server response
kubectl get nodes
```

Once the nodes are `Ready`, check for the `disaster-zone` namespace:
```bash
kubectl get ns
```

**Expected Result**:
The namespace `disaster-zone` **does not exist** in the list. The cluster has successfully rolled back in time, erasing the simulated changes and proving database restoration functionality.
