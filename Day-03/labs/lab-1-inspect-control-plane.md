# Lab 1: Inspecting Kubernetes Control Plane Components

In this lab, you will explore the physical deployments of the core control plane components, examine their startup flags, and compare self-hosted clusters with managed Kubernetes offerings (GKE/EKS/AKS).

---

## 🏃 Step 1: Query the Control Plane Pods
In clusters created by tools like `kubeadm` or `kind`, the control plane components run as specialized pods in the `kube-system` namespace.

List all pods in the `kube-system` namespace:
```bash
kubectl get pods -n kube-system -o wide
```

**Expected Output:**
You should see pods for the API Server, Scheduler, Controller Manager, and etcd. They will have names resembling:
```
NAME                                           READY   STATUS    RESTARTS   AGE     IP           NODE
etcd-k8s-internals-control-plane               1/1     Running   0          5m      172.18.0.3   k8s-internals-control-plane
kube-apiserver-k8s-internals-control-plane     1/1     Running   0          5m      172.18.0.3   k8s-internals-control-plane
kube-controller-manager-k8s-internals-co...    1/1     Running   0          5m      172.18.0.3   k8s-internals-control-plane
kube-scheduler-k8s-internals-control-plane     1/1     Running   0          5m      172.18.0.3   k8s-internals-control-plane
```

> [!NOTE]
> Notice that the IP address of all these control plane components is the same (`172.18.0.3`—the host IP of the control plane node). This is because they run in the **host's network namespace** (using `hostNetwork: true`).

---

## 🏃 Step 2: Examine Component Configuration Flags
The control plane components are configured via CLI arguments passed at startup. Let's inspect the `kube-apiserver`.

Describe the API Server pod:
```bash
kubectl describe pod kube-apiserver-k8s-internals-control-plane -n kube-system
```

Look at the **Command** section in the output. It displays the operational configuration of the API server:
```yaml
Command:
  kube-apiserver
  --advertise-address=172.18.0.3
  --allow-privileged=true
  --authorization-mode=Node,RBAC
  --client-ca-file=/etc/kubernetes/pki/ca.crt
  --enable-admission-plugins=NodeRestriction
  --enable-bootstrap-token-auth=true
  --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
  --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
  --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
  --etcd-servers=https://127.0.0.1:2379
  --service-account-key-file=/etc/kubernetes/pki/sa.pub
  --service-cluster-ip-range=10.96.0.0/16
  --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
  --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
```

### Key Parameters to Analyze:
1. `--authorization-mode=Node,RBAC`: Confirms that the API Server will authorize node-specific requests using Node Auth first, then standard Role-Based Access Control.
2. `--etcd-servers=https://127.0.0.1:2379`: Points the API Server to the etcd server running locally.
3. `--enable-admission-plugins=NodeRestriction`: Restricts what a Kubelet can modify (preventing compromised worker nodes from altering cluster-wide settings).

---

## 🏃 Step 3: Inspect the Local Manifests (Static Pods)
How did these pods start if the API server and scheduler weren't running yet? They are **Static Pods** managed directly by the Kubelet on the control-plane node.

Let's exec into the control plane node to view the files. If you are using Kind:
```bash
docker exec -it k8s-internals-control-plane bash
```

Once inside the container (which acts as the master node host):
```bash
ls -l /etc/kubernetes/manifests/
```

**Output:**
```
total 16
-rw------- 1 root root 2235 May 25 14:00 etcd.yaml
-rw------- 1 root root 3855 May 25 14:00 kube-apiserver.yaml
-rw------- 1 root root 3320 May 25 14:00 kube-controller-manager.yaml
-rw------- 1 root root 1438 May 25 14:00 kube-scheduler.yaml
```

Inspect one of these manifests (e.g., `kube-scheduler.yaml`):
```bash
cat /etc/kubernetes/manifests/kube-scheduler.yaml
```
Observe that these are standard Kubernetes Pod spec manifests. When the Kubelet service boots up, it reads this directory and spawns these pods locally. If you edit these files, the Kubelet will instantly detect the changes and recreate the components.

Exit the container:
```bash
exit
```

---

## ⚡ Production Realities: Managed vs. Self-Hosted
In this lab, you inspected a **Self-Hosted** (or local emulator) cluster. In production cloud environments, this changes:

### AWS EKS / GCP GKE / Azure AKS (Managed Control Planes)
* If you run `kubectl get pods -n kube-system` in an EKS or GKE cluster, you **will not** see `kube-apiserver`, `etcd`, or `kube-scheduler` pods.
* **Why?** The cloud provider hosts the control plane in a dedicated, isolated AWS/GCP account. They manage the VMs, scale them, back up etcd, and expose only the API endpoint.
* You cannot view `/etc/kubernetes/manifests` or modify flags directly on EKS/GKE master nodes. Instead, you configure parameters through cloud API settings (e.g., enabling logs, setting cluster endpoints).
* **Managed Node Groups:** Only the worker nodes exist in your cloud account. The Kubelets on these nodes are configured to securely call the cloud-managed API gateway endpoint.
