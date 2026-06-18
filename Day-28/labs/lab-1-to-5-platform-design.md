# 🧪 Labs 1 to 5: Production Platform Engineering & Design

This lab manual guides you through building a multi-tier production platform, configuring high availability, distributing workloads across zones, deploying telemetry pipelines, and securing the API boundary.

---

## 🛠️ Prerequisites
* A running Kubernetes Cluster (multi-node setup like Kind with 3 worker nodes is recommended).
* `kubectl` CLI installed and configured.
* Access to internet-facing repositories to pull metrics images.

---

## 🧪 Lab 1: Build a Multi-Tier Platform

In this lab, we will bootstrap a 3-tier production platform containing an ingress routing gateway, a stateless API microservice tier, and a caching backend.

### Step 1.1: Create Namespace and Deploy Web App Pods
Apply the multi-tier deployment manifest containing resource limits and startup probes:
```bash
kubectl apply -f ../manifests/production-app-tier.yaml
```

**Expected Output:**
```text
namespace/production-app created
poddisruptionbudget.policy/backend-pdb created
deployment.apps/ecom-backend created
horizontalpodautoscaler.autoscaling/ecom-backend-hpa created
```

### Step 1.2: Verify the Workloads
Check if the namespace resources have spawned:
```bash
kubectl get all -n production-app
```

**Expected Output:**
```text
NAME                                READY   STATUS    RESTARTS   AGE
pod/ecom-backend-5c68f94946-1234a   1/1     Running   0          30s
pod/ecom-backend-5c68f94946-5678b   1/1     Running   0          30s
pod/ecom-backend-5c68f94946-9012c   1/1     Running   0          30s

NAME                           TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
deployment.apps/ecom-backend   3/3         3            3             30s
```

---

## 🧪 Lab 2: Implement HA Control Plane Architectures

In this lab, we will inspect the active components of a multi-master control plane.

### Step 2.1: Locate Control Plane Pods
Examine the pods running in the `kube-system` namespace. In a production cluster, you will see multiple replicas of `kube-apiserver`, `kube-controller-manager`, and `kube-scheduler` bound to different control plane nodes.
```bash
kubectl get pods -n kube-system -o wide | grep -E "api|controller|scheduler"
```

### Step 2.2: Verify Leader Election Status
To see which controller-manager is currently active (holds the leader lease lock):
```bash
kubectl get lease -n kube-system
```
**Expected Output:**
```text
NAME                      HOLDER                                              AGE
kube-controller-manager   master-node-1_695029ea-0306-4bba-9577-d5d14df5a02a  12d
kube-scheduler            master-node-2_e799276d-1145-4231-897d-6060938ff5d1  12d
```

---

## 🧪 Lab 3: Configure Multi-Zone Deployments

In this lab, we will configure worker node scheduling constraints to guarantee that replicas are distributed evenly across physical availability zones.

### Step 3.1: Labels Inspection
Ensure your worker nodes have zone labels applied (standard on cloud environments, or mocked in Kind):
```bash
kubectl get nodes --show-labels | grep "topology.kubernetes.io/zone"
```

### Step 3.2: Verify Pod Zone Distribution
Check which zones the application pods were scheduled into using custom jsonpath filters:
```bash
kubectl get pods -n production-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'
```
Compare the target nodes with node zones to verify that the scheduler has balanced the pods across zones.

---

## 🧪 Lab 4: Deploy a Production Observability Stack

In this lab, we will configure a Prometheus alert routing rule to capture high control plane latency.

### Step 4.1: Deploy Prometheus Rule
Apply the alerting configuration containing the threshold rules:
```bash
kubectl apply -f ../manifests/prom-alerts-rules.yaml
```

**Expected Output:**
```text
prometheusrule.monitoring.coreos.com/platform-ha-alert-rules created
```

### Step 4.2: Verify the Rules inside Prometheus API
Forward Prometheus UI ports to your machine and check the Alerts tab:
```bash
# Mock check commands
kubectl get prometheusrule -n production-app
```

---

## 🧪 Lab 5: Secure the Platform

In this lab, we will enforce strict namespace isolation policies to implement a zero-trust network environment.

### Step 5.1: Apply Default Deny-All Network Policy
Apply the default-deny rules to block all namespace transit:
```bash
kubectl apply -f ../manifests/security-policies.yaml
```

**Expected Output:**
```text
networkpolicy.networking.k8s.io/default-deny-all created
networkpolicy.networking.k8s.io/allow-ingress-to-backend created
ciliumnetworkpolicy.cilium.io/secure-backend-cilium created
```

### Step 5.2: Test Policy Enforcement
Attempt to spin up an unauthorized pod and curl the backend server:
```bash
kubectl run test-curl --rm -i --tty --image=curlimages/curl -n production-app -- sh
# Inside pod, try:
curl -I http://ecom-backend:8080/healthz
```
If the policy is functioning correctly, the request should timeout.
```text
curl: (28) Connection timed out after 10000 milliseconds
```
Only pods matching the Ingress labels defined in `allow-ingress-to-backend` NetworkPolicy will be allowed to pass.
