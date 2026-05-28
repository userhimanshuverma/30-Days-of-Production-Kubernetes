# 🛠️ Lab 1: Working with ClusterIP Services

In this lab, you will deploy a backend application, expose it via a default `ClusterIP` Service, and examine how Kubernetes handles internal load balancing and connection routing.

---

## Prerequisites
* A running Kubernetes cluster (Kind, Minikube, or custom cluster)
* `kubectl` configured to point to your cluster

---

## Step 1: Deploy the Web Backend Workload
Create the deployment and the service by applying the manifest from the repository:
```bash
kubectl apply -f manifests/01-clusterip-deployment-service.yaml
```

**Expected Output**:
```text
deployment.apps/web-backend created
service/web-backend-service created
```

---

## Step 2: Inspect the Service Metadata
Let's check the Service details:
```bash
kubectl get svc web-backend-service
```

**Expected Output**:
```text
NAME                  TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
web-backend-service   ClusterIP   10.96.14.22    <none>        80/TCP    15s
```

Note down the **ClusterIP** (e.g., `10.96.14.22`). This is the virtual IP address allocated to your service.

Let's inspect the Service in detail:
```bash
kubectl describe svc web-backend-service
```

**Expected Output**:
```text
Name:              web-backend-service
Namespace:         default
Labels:            app=web-backend
Annotations:       <none>
Selector:          app=web-backend
Type:              ClusterIP
IP Family Policy:  SingleStack
IP Families:       IPv4
IP:                10.96.14.22
IPs:               10.96.14.22
Port:              http  80/TCP
TargetPort:        8080/TCP
Endpoints:         10.244.1.5:8080,10.244.1.6:8080,10.244.2.12:8080
Session Affinity:  None
Events:            <none>
```

Identify the **Endpoints** field. It contains the actual IP addresses of the three pods running under our deployment.

---

## Step 3: Test Routing inside the Cluster
Since the ClusterIP is internal-only, you cannot access it from your developer laptop. We will deploy the `dns-debug` troubleshooting pod to run requests from inside the cluster:

```bash
kubectl apply -f manifests/04-dns-debug-pod.yaml
```

Wait for the pod to become ready:
```bash
kubectl wait --for=condition=Ready pod/dns-debug --timeout=60s
```

Now, execute a shell inside the `dns-debug` container and send requests to the service's ClusterIP:
```bash
kubectl exec -it dns-debug -- curl http://10.96.14.22
```

*(Replace `10.96.14.22` with your actual ClusterIP)*

**Expected Output**:
```text
Hello from the Kubernetes Networking Backend!
```

---

## Step 4: Verify L4 Load Balancing
Let's run a loop to see if the traffic is split across the three pods. Each pod returns its unique Pod Name. Run this command in your terminal:

```bash
for i in {1..10}; do kubectl exec -it dns-debug -- curl -s http://web-backend-service | grep "pod: "; done
```

**Expected Output**:
```text
    <p>Served by pod: web-backend-7bd5c85b54-jkg8f</p>
    <p>Served by pod: web-backend-7bd5c85b54-ffp2x</p>
    <p>Served by pod: web-backend-7bd5c85b54-m9lqv</p>
    <p>Served by pod: web-backend-7bd5c85b54-jkg8f</p>
    ...
```

Observe that the service distributes requests across the various Pod names. Because kube-proxy uses random probability algorithms, traffic is spread evenly across the active backend pods.
