# Lab 3: Exploring Scheduler Behavior

In this lab, you will explore the scheduling mechanics of Kubernetes. You will learn how to bypass the scheduler entirely, schedule pods using node selectors, and test taints and tolerations.

---

## 🏃 Step 1: Bypass the Scheduler (Manual Scheduling)
When you submit a Pod manifest, the API Server saves it without a host assigned (`spec.nodeName` is empty). The scheduler watches for such pods and updates `spec.nodeName`. 

If we specify `spec.nodeName` at the time of creation, the Scheduler ignores the Pod entirely because it is already bound. Even if the Scheduler component is stopped, this pod will schedule!

Let's test this. Write the following manifest to `manifests/02-manual-pod.yaml`:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: manual-nginx
  namespace: default
spec:
  nodeName: k8s-internals-worker # Replace with your actual worker node name from 'kubectl get nodes'
  containers:
  - name: nginx
    image: nginx:alpine
```
*(Wait, let's first list our nodes to verify our node names)*:
```bash
kubectl get nodes
```
*(If your worker node is named `k8s-internals-worker`, keep the file as-is. If it is `minikube` or another name, adjust the `nodeName` field accordingly).*

Create the pod:
```bash
kubectl apply -f manifests/02-manual-pod.yaml
```

Verify that the pod is immediately placed in the `Running` state:
```bash
kubectl get pod manual-nginx -o wide
```

If you view the events for this pod:
```bash
kubectl get events --field-selector involvedObject.name=manual-nginx
```
You will notice there is **no** `Scheduled` event from the `default-scheduler`. The kubelet on `k8s-internals-worker` saw the pod was assigned to it in etcd, pulled the image, and ran it.

---

## 🏃 Step 2: Set Node Labels and Use nodeSelector
`nodeSelector` is the simplest form of node selection constraint. It uses key-value label matching.

First, label one of your worker nodes:
```bash
kubectl label nodes k8s-internals-worker disktype=ssd
```

Now, create a pod that requests this specific label. Write the following manifest to `manifests/04-scheduler-scoring-demo.yaml`:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: labeled-nginx
  namespace: default
spec:
  nodeSelector:
    disktype: ssd
  containers:
  - name: nginx
    image: nginx:alpine
```

Apply the configuration:
```bash
kubectl apply -f manifests/04-scheduler-scoring-demo.yaml
```

Verify the pod is running on the labeled node:
```bash
kubectl get pod labeled-nginx -o wide
```

---

## 🏃 Step 3: Test Taints and Tolerations
Taints allow a node to **repel** a set of pods. Let's taint our second worker node (`k8s-internals-worker2`) so that no pods can schedule on it unless they have a toleration.

Add a taint to `k8s-internals-worker2`:
```bash
kubectl taint nodes k8s-internals-worker2 tier=production:NoSchedule
```

Let's attempt to deploy a standard deployment without a toleration. Create a deployment manifest and apply it:
```bash
kubectl create deployment untolerated-nginx --image=nginx:alpine --replicas=3
```

Watch the pods:
```bash
kubectl get pods -o wide -l app=untolerated-nginx
```

**Observation:**
If you have a 3-node cluster (1 control-plane, 2 workers), all 3 replicas of the deployment will schedule onto `k8s-internals-worker`. None will schedule on `k8s-internals-worker2` because of the taint. If you cordon or drain `k8s-internals-worker`, the pods will stay `Pending` because they do not tolerate the taint on `k8s-internals-worker2`.

Let's clean up:
```bash
kubectl delete pod manual-nginx labeled-nginx
kubectl delete deployment untolerated-nginx
kubectl label nodes k8s-internals-worker disktype-
kubectl taint nodes k8s-internals-worker2 tier=production:NoSchedule-
```
