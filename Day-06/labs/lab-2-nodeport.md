# 🛠️ Lab 2: Exposing Applications with NodePort Services

In this lab, you will configure a NodePort Service to make your application reachable from outside the Kubernetes cluster by binding a specific port on all host nodes.

---

## Step 1: Deploy the NodePort Service
Apply the NodePort manifest:
```bash
kubectl apply -f manifests/02-nodeport-service.yaml
```

**Expected Output**:
```text
service/web-backend-nodeport created
```

---

## Step 2: Inspect the Service Port Bindings
List the services to verify the creation:
```bash
kubectl get svc web-backend-nodeport
```

**Expected Output**:
```text
NAME                   TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
web-backend-nodeport   NodePort   10.99.122.84   <none>        80:30080/TCP   10s
```

Look at the `PORT(S)` column: `80:30080/TCP`.
* `80`: The internal port where the Service is exposed inside the cluster.
* `30080`: The node port bound on every physical worker node in the cluster.

---

## Step 3: Identify Node IP Addresses
To access the service externally, you need to find the IP addresses of your cluster nodes:
```bash
kubectl get nodes -o wide
```

**Expected Output**:
```text
NAME                 STATUS   ROLES           AGE   VERSION   INTERNAL-IP
kind-control-plane   Ready    control-plane   24h   v1.27.3   172.18.0.2
kind-worker          Ready    <none>          24h   v1.27.3   172.18.0.3
kind-worker2         Ready    <none>          24h   v1.27.3   172.18.0.4
```

Here, our nodes have internal IPs: `172.18.0.2`, `172.18.0.3`, and `172.18.0.4`.

---

## Step 4: Test Connection Externally
From your local terminal (outside the cluster), curl any of the node IPs on port `30080`:

```bash
curl http://172.18.0.3:30080
```

*(If you are running Minikube, you can run `minikube service web-backend-nodeport --url` to get the correct URL).*

**Expected Output**:
```text
Hello from the Kubernetes Networking Backend!
```

---

## Step 5: Understand Port Bindings on the Host
If you have SSH access to one of your worker nodes, you can verify that `kube-proxy` is listening on port `30080` (or configured iptables to intercept it):

```bash
# SSH into a node (e.g. for kind clusters)
docker exec -it kind-worker ss -tulpn | grep 30080
```

**Expected Output**:
```text
tcp   LISTEN 0      1024         0.0.0.0:30080      0.0.0.0:*      users:(("kube-proxy",pid=123,fd=10))
```

This confirms that `kube-proxy` listens on the node port to capture external incoming connections, routing them to the backend pod endpoints.
