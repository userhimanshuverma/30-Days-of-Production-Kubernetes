# Lab 2: Implementing Zero-Trust Network Policies

In this lab, you will deploy a multi-tier application (Frontend, Backend, PostgreSQL Database) and apply Network Policies to secure it using zero-trust networking principles.

---

## Architecture of the Secure Target

```
[ Ingress / User ]
       │
       ▼
[ prod-frontend ] (Port 80)
       │
       ▼ (Permit Ingress)
[ prod-backend ]  (Port 8080)
       │
       ▼ (Permit Ingress)
[ prod-postgres ] (Port 5432)
```

---

## Step 1: Deploy the Workloads

Apply the base application deployments and services:

```bash
kubectl apply -f ../manifests/secure-app-deployment.yaml
```

Verify that all pods are running and note their IPs:
```bash
kubectl get pods -l app.kubernetes.io/part-of=secure-app -o wide
```

Test that all components can communicate initially. Let's verify if the frontend can connect to Postgres directly (this should be blocked in a secure environment but is currently allowed):
```bash
# 1. Get the name of the frontend pod
FRONTEND_POD=$(kubectl get pods -l app=prod-frontend -o jsonpath='{.items[0].metadata.name}')

# 2. Check connection from frontend pod to postgres database service (should return PG banner/connection timeout)
kubectl exec $FRONTEND_POD -- nc -zvw3 prod-postgres 5432
```
**Expected Output:**
```
Connection to prod-postgres 5432 port [tcp/postgresql] succeeded!
```
*Because Kubernetes defaults to "Default Allow", any pod can access the database directly. Let's fix this security issue.*

---

## Step 2: Apply Global Default-Deny-All Network Policy

To implement zero-trust, we block all ingress and egress connections by default in the namespace.

Apply the default-deny policy:
```bash
kubectl apply -f ../manifests/default-deny.yaml
```

Now, re-run the connection test:
```bash
kubectl exec $FRONTEND_POD -- nc -zvw3 prod-postgres 5432
```
**Expected Output:**
```
nc: prod-postgres (10.96.x.x:5432): Connection timed out
```
The packet is silently dropped. In fact, if you try to query DNS now, it will fail because CoreDNS egress is also blocked!

---

## Step 3: Configure DNS and Frontend Network Policies

To allow the frontend to resolve addresses and receive ingress traffic from outside the cluster, apply the frontend-specific policy:

```bash
kubectl apply -f ../manifests/frontend-policy.yaml
```

This policy does two things:
1. Allows DNS queries (Egress on UDP/TCP port 53 to namespaces labeled `kubernetes.io/metadata.name: kube-system`).
2. Allows Ingress on port `80` from any external IP, and restricts Egress to only talk to the `prod-backend` Pod on port `8080`.

---

## Step 4: Configure Backend Network Policies

Apply the backend policy:
```bash
kubectl apply -f ../manifests/backend-policy.yaml
```

This policy:
1. Allows Ingress on port `8080` only if the source pod has label `app: prod-frontend`.
2. Allows Egress to DNS (port 53) and Postgres database Pods (port 5432) with label `app: prod-postgres`.

---

## Step 5: Secure the Database

Apply the database policy:
```bash
kubectl apply -f ../manifests/database-policy.yaml
```

This policy:
1. Allows Ingress on port `5432` only from source pods with label `app: prod-backend`.
2. Blocks all outbound egress from the database container.

---

## Step 6: Validate Security Compliance

Let's run connectivity checks to verify the security controls:

1. **Verify Frontend to Backend (Expected: SUCCESS):**
```bash
kubectl exec $FRONTEND_POD -- nc -zvw3 prod-backend 8080
```
*Result: Succeeded.*

2. **Verify Frontend to Postgres Database (Expected: BLOCKED):**
```bash
kubectl exec $FRONTEND_POD -- nc -zvw3 prod-postgres 5432
```
*Result: Connection timed out.*

3. **Verify Backend to Postgres Database (Expected: SUCCESS):**
```bash
BACKEND_POD=$(kubectl get pods -l app=prod-backend -o jsonpath='{.items[0].metadata.name}')
kubectl exec $BACKEND_POD -- nc -zvw3 prod-postgres 5432
```
*Result: Succeeded.*

4. **Verify Database attempting to connect to external sites (Expected: BLOCKED):**
```bash
DB_POD=$(kubectl get pods -l app=prod-postgres -o jsonpath='{.items[0].metadata.name}')
kubectl exec $DB_POD -- nc -zvw3 google.com 443
```
*Result: Connection timed out.*

---

## Step 7: How to Debug Blocked Traffic

If you run into issues where networking is failing and you suspect Network Policies:

1. **Check if a Pod is Selected by Policies:**
```bash
kubectl describe pod $DB_POD
```
*Look at the output. If a policy is actively selecting the pod, you will see it listed under the Networking status.*

2. **List all Network Policies in the namespace:**
```bash
kubectl get netpol
```

3. **Examine Policy Selectors:**
```bash
kubectl describe netpol database-policy
```
Ensure that the `Spec.PodSelector` matches the database pod labels exactly, and the `Ingress.From.PodSelector` matches the backend app labels exactly. Typos in labels are the number one cause of broken applications in production network policy rollouts.

---

## Clean Up
```bash
kubectl delete -f ../manifests/
```
 Isolation rules are instantly removed, and the network namespace default configuration returns to allow-all.
