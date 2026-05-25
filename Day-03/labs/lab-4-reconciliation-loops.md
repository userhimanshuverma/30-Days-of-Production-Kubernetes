# Lab 4: Observing Reconciliation Loops

In this lab, you will watch reconciliation in action. You will observe how the ReplicaSet controller continuously monitors the cluster, detects state deviations, and runs reconciliation logic to resolve them. You will also learn about the separation of concerns between controllers.

---

## 🏃 Step 1: Create a Deployment and Watch the ReplicaSet
We will create a deployment which in turn creates a ReplicaSet to manage pod lifecycles.

Write the following manifest to `manifests/01-nginx-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reconcile-demo
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: reconcile-demo
  template:
    metadata:
      labels:
        app: reconcile-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
```

Apply the deployment:
```bash
kubectl apply -f manifests/01-nginx-deployment.yaml
```

Now, list the ReplicaSet:
```bash
kubectl get replicaset -l app=reconcile-demo
```
**Output:**
```
NAME                        DESIRED   CURRENT   READY   AGE
reconcile-demo-69c57d77c4   3         3         3       10s
```

---

## 🏃 Step 2: Simulate Actual State Mismatch (Manual Eviction)
Open two terminal windows (or run a background watch).

In terminal 1, start watching the pods:
```bash
kubectl get pods -w -l app=reconcile-demo
```

In terminal 2, delete one of the pods manually:
```bash
# Get a pod name first
POD_NAME=$(kubectl get pods -l app=reconcile-demo -o jsonpath='{.items[0].metadata.name}')

# Delete it
kubectl delete pod $POD_NAME
```

Observe terminal 1. You will see something like this:
```
reconcile-demo-69c57d77c4-abc12   Running   Terminating   ...
reconcile-demo-69c57d77c4-xyz98   Pending   Pending       ...
reconcile-demo-69c57d77c4-xyz98   ContainerCreating   ...
```

### Analysis:
What happened here?
1. The **ReplicaSet Controller** watches for changes to pods with matching labels.
2. The deletion of `reconcile-demo-...-abc12` triggers a Pod Delete event.
3. The controller manager's work queue processes the event and fires `Reconcile()`.
4. Inside `Reconcile()`:
   * **Desired State:** 3 replicas (defined in the ReplicaSet spec).
   * **Actual State:** 2 pods remaining.
   * **Delta:** -1 pod.
5. The controller immediately issues a POST request to the API Server to create a new Pod.
6. The new Pod `reconcile-demo-...-xyz98` is created in etcd, scheduler schedules it, and Kubelet boots it.

---

## 🏃 Step 3: Explore Separation of Concerns (Creating vs. Running)
A common beginner misconception is that the ReplicaSet controller runs containers. It does not. Its **only** responsibility is ensuring the correct number of Pod *API objects* exist in etcd.

Let's prove this. We will scale our deployment up, but we will configure the Pods to use an invalid image name. The containers will fail to pull, but let's see how the ReplicaSet controller behaves.

Update the image of the deployment to a non-existent tag:
```bash
kubectl set image deployment/reconcile-demo nginx=nginx:this-tag-does-not-exist
```

Wait 5 seconds, then list the ReplicaSet:
```bash
kubectl get replicaset -l app=reconcile-demo
```
**Output:**
```
NAME                        DESIRED   CURRENT   READY   AGE
reconcile-demo-754d92bd4b   3         3         0       15s
reconcile-demo-69c57d77c4   0         0         0       5m
```
*Note that DESIRED is 3, CURRENT is 3, but READY is 0.*

Query the pods:
```bash
kubectl get pods -l app=reconcile-demo
```
**Output:**
```
NAME                              READY   STATUS             RESTARTS   AGE
reconcile-demo-754d92bd4b-f72qw   0/1     ImagePullBackOff   0          45s
reconcile-demo-754d92bd4b-tq2lm   0/1     ImagePullBackOff   0          45s
reconcile-demo-754d92bd4b-vjx89   0/1     ImagePullBackOff   0          45s
```

### Analysis:
From the ReplicaSet Controller's perspective, its reconciliation loop is **successful**. It was told to ensure that 3 Pod objects with the template `nginx:this-tag-does-not-exist` exist. It called the API server and created 3 Pod objects.
The fact that containerd cannot pull the image is a downstream runtime failure (Kubelet level), not a ReplicaSet Controller reconciliation failure. The controller has done its job.

Clean up:
```bash
kubectl delete deployment reconcile-demo
```
