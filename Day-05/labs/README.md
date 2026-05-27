# 🛠️ Day 5 Hands-On Labs: Deployments, Strategies & Recovery

In today's labs, you will work through the real-world mechanics of Kubernetes reconciliation, self-healing, rolling updates, canary routing, and rollback procedures.

---

## 📋 Prerequisites
Before starting, ensure you have:
1. A running Kubernetes cluster (Kind, Minikube, or a remote cloud cluster).
2. The `kubectl` CLI installed and configured.
3. Access to a terminal within this repository directory.

To verify your cluster connection, run:
```bash
kubectl cluster-info
```

---

## 🧪 Lab 1: Deploying workloads Declaratively

We will create our first Deployment using the manifest located at [01-basic-deployment.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-05/manifests/01-basic-deployment.yaml).

### Step 1: Apply the manifest
Run the following command to apply the basic deployment:
```bash
kubectl apply -f ../manifests/01-basic-deployment.yaml
```
*Expected Output:*
```text
deployment.apps/payment-processor-basic created
```

### Step 2: Inspect the ownership tree
Query the resources created in the cluster. Notice how the Deployment created a ReplicaSet, which in turn created 3 Pods:
```bash
kubectl get deployment,rs,pods -l app=payment-processor
```
*Expected Output:*
```text
NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/payment-processor-basic   3/3     3            3           22s

NAME                                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/payment-processor-basic-5b87dc744b   3         3         3       22s

NAME                                           READY   STATUS    RESTARTS   AGE
pod/payment-processor-basic-5b87dc744b-aaa11   1/1     Running   0          22s
pod/payment-processor-basic-5b87dc744b-bbb22   1/1     Running   0          22s
pod/payment-processor-basic-5b87dc744b-ccc33   1/1     Running   0          22s
```

Notice how the Pod names are prefixed with the ReplicaSet hash (`5b87dc744b`), which is derived from the template specification.

---

## 📈 Lab 2: Scaling workloads manually

Let's scale our deployment from 3 replicas up to 5 replicas.

### Step 1: Run the scale command
```bash
kubectl scale deployment/payment-processor-basic --replicas=5
```
*Expected Output:*
```text
deployment.apps/payment-processor-basic scaled
```

### Step 2: Observe the ReplicaSet reaction
Inspect the pods immediately:
```bash
kubectl get rs,pods -l app=payment-processor
```
You will see that the ReplicaSet was updated to desire 5 replicas and has immediately spawned two new Pods in the `Pending` or `ContainerCreating` phase.

---

## 🩹 Lab 3: Triggering & Observing Self-Healing

We will simulate a node outage or container failure by manually deleting a Pod in the deployment.

### Step 1: Monitor events in real-time
In a separate terminal window, start monitoring Pod events:
```bash
kubectl get pods -l app=payment-processor -w
```

### Step 2: Delete one of the Pods
In your primary terminal, delete one of the running pods:
```bash
# Replace pod name with one of your actual running pod names
kubectl delete pod payment-processor-basic-5b87dc744b-aaa11
```

### Step 3: Observe the event log
In your monitoring window, you will observe the following sequence:
1. The deleted pod transitions to `Terminating`.
2. Simultaneously, a brand-new replacement pod is created (e.g. `payment-processor-basic-5b87dc744b-xyz99`) and transitions to `Pending` -> `Running` -> `Ready`.
3. The old pod is completely deleted from the API.

This happens because the ReplicaSet Controller reconciliation loop checks the state: `Desired: 5, Actual: 4`. It immediately issues a call to create a new pod to heal the gap.

---

## 🔄 Lab 4: Performing a Zero-Downtime Rolling Update

Now, we will trigger a Rolling Update by deploying the manifest [02-rolling-update.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-05/manifests/02-rolling-update.yaml) which configures `maxSurge: 1` and `maxUnavailable: 0`.

### Step 1: Apply the rolling update manifest
```bash
kubectl apply -f ../manifests/02-rolling-update.yaml
```
*Expected Output:*
```text
deployment.apps/payment-processor-rolling created
```

### Step 2: Trigger an update (Change the Image Version)
We will update the container image from `nginxinc/nginx-unprivileged:1.25-alpine` to `nginxinc/nginx-unprivileged:1.26-alpine`:
```bash
kubectl set image deployment/payment-processor-rolling payment-api=nginxinc/nginx-unprivileged:1.26-alpine --record
```
*(Note: `--record` flag stores the command in the revision history annotations).*

### Step 3: Monitor rollout progress
Check the rollout status:
```bash
kubectl rollout status deployment/payment-processor-rolling
```
*Expected Output:*
```text
Waiting for deployment "payment-processor-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "payment-processor-rolling" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "payment-processor-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
...
deployment "payment-processor-rolling" successfully rolled out
```

If you run `kubectl get rs` during the rollout, you will see two ReplicaSets: the old one scaling down, and the new one scaling up.

---

## 🚨 Lab 5: Simulating a Failed Deployment

Let's test what happens when a rollout is bad. We will apply [05-failed-deployment.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-05/manifests/05-failed-deployment.yaml). It uses a broken startup probe `/healthz-broken` which will fail to answer, causing the rollout to stall.

### Step 1: Deploy the broken manifest
```bash
kubectl apply -f ../manifests/05-failed-deployment.yaml
```

### Step 2: Inspect status
Check the rollout status:
```bash
kubectl rollout status deployment/payment-processor-failed
```
The command will hang indefinitely, displaying:
```text
Waiting for deployment "payment-processor-failed" rollout to finish: 1 out of 3 new replicas have been updated...
```

### Step 3: Inspect Pod phases
Check the Pod status:
```bash
kubectl get pods -l app=payment-processor,version=1.2.0-broken
```
*Expected Output:*
```text
NAME                                        READY   STATUS    RESTARTS   AGE
payment-processor-failed-5d4fbb8b56-aaa11   0/1     Running   0          45s
```
The pod is in state `Running` but is **not Ready** (`0/1` readiness). Because `maxUnavailable: 0` is set, Kubernetes will not delete any of the older, stable pods. The rollout is stuck, protecting your production users from receiving broken code.

---

## ⏪ Lab 6: Reverting Changes via Rollback

Since the deployment is stalled, we must roll back to restore peace.

### Step 1: View the deployment revision history
```bash
kubectl rollout history deployment/payment-processor-failed
```
*Expected Output:*
```text
REVISION  CHANGE-CAUSE
1         <none>
2         kubectl apply --filename=../manifests/05-failed-deployment.yaml
```

### Step 2: Undo the rollout
```bash
kubectl rollout undo deployment/payment-processor-failed
```
*Expected Output:*
```text
deployment.apps/payment-processor-failed rolled back
```

If you check the pods now, you will see that the unready pod is terminated, and the stable revision has been fully restored.

---

## 🐤 Lab 7: Implementing Canary Deployments

We will simulate a Canary rollout using vanilla Kubernetes label routing.

### Step 1: Deploy the Stable workload (v1)
Apply version 1 and its service:
```bash
kubectl apply -f ../manifests/03-canary-v1.yaml
kubectl apply -f ../manifests/03-canary-service.yaml
```

### Step 2: Deploy the Canary workload (v2)
Apply version 2 (with 1 replica):
```bash
kubectl apply -f ../manifests/03-canary-v2.yaml
```

### Step 3: Test traffic distribution
Spawn a temporary interactive test container in the cluster to curl the service in a loop:
```bash
kubectl run curl-test --image=radial/busyboxplus:curl -i --tty --rm
```
Once inside the shell, execute this loop:
```bash
while true; do curl -s http://payment-processor-canary-svc/version; echo ""; sleep 1; done
```
*Expected Output:*
```text
v1
v1
v2
v1
v1
v1
v2
```
You will observe that roughly 25% of the requests land on `v2` (canary) and 75% on `v1` (stable). This is L4 round-robin load balancing at work. To exit, type `exit`.

---

## 🔵🟢 Lab 8: Implementing Blue/Green Deployments

Let's test Blue/Green cutover by patching the service selector label.

### Step 1: Deploy Blue and Green workloads, and the service
```bash
kubectl apply -f ../manifests/04-blue-green-active.yaml
kubectl apply -f ../manifests/04-blue-green-preview.yaml
kubectl apply -f ../manifests/04-service-blue-green.yaml
```

### Step 2: Verify active environment is Blue
Launch the curl container:
```bash
kubectl run curl-test --image=radial/busyboxplus:curl -i --tty --rm
```
In the container, curl the service:
```bash
curl http://payment-processor-bg-svc/version
```
It should return `blue`. Type `exit` to close the pod.

### Step 3: Switchover to Green (Patch the Service selector)
Update the service selector label to point to `color: green`:
```bash
kubectl patch service payment-processor-bg-svc -p '{"spec":{"selector":{"color":"green"}}}'
```
*Expected Output:*
```text
service/payment-processor-bg-svc patched
```

### Step 4: Verify traffic has cut over
Launch the curl container again:
```bash
kubectl run curl-test --image=radial/busyboxplus:curl -i --tty --rm
```
Curl the service:
```bash
curl http://payment-processor-bg-svc/version
```
It will instantly return `green`. Type `exit` to close.

---

## 🧹 Clean Up
To delete all resources created in today's labs:
```bash
kubectl delete deployment -l app.kubernetes.io/name=payment-processor-canary
kubectl delete deployment -l app.kubernetes.io/name=payment-processor-bg
kubectl delete deployment payment-processor-basic payment-processor-rolling payment-processor-failed
kubectl delete svc payment-processor-canary-svc payment-processor-bg-svc
```
