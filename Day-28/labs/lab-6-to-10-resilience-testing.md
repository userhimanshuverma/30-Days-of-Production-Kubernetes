# 🧪 Labs 6 to 10: Platform Chaos & Production Readiness Reviews

This lab manual guides you through injecting failures, testing resilience parameters, scaling workloads, executing peer architecture evaluations, and conducting a complete Production Readiness Assessment.

---

## 🧪 Lab 6: Simulate Failure Domains

In this lab, we will simulate a zone outage by cordoning all nodes inside a specific availability zone.

### Step 6.1: Identify Node Zone Groups
List your worker nodes and group them by zone:
```bash
kubectl get nodes -L topology.kubernetes.io/zone
```

### Step 6.2: Cordon the target zone nodes
Simulate an outage by marking all nodes in `us-east-1b` as unschedulable:
```bash
for node in $(kubectl get nodes -l topology.kubernetes.io/zone=us-east-1b -o jsonpath='{.items[*].metadata.name}'); do
  kubectl cordon $node
done
```

**Expected Output:**
```text
node/worker-node-2 cordoned
```

---

## 🧪 Lab 7: Validate Resilience & Recovery

We will force-terminate our backend pods to verify if replacement workloads schedule in the healthy zones (`us-east-1a` and `us-east-1c`) without violating PodDisruptionBudgets (PDB).

### Step 7.1: Force Delete Running Pods
Delete the pods running in the cordoned zone:
```bash
# Force delete pods to trigger replication controller reschedule
kubectl delete pods -n production-app -l app=ecom-backend --grace-period=0 --force
```

### Step 7.2: Verify Replacement scheduling
Check pod placement across remaining nodes:
```bash
kubectl get pods -n production-app -o wide
```
Ensure all pods have scheduled on nodes in `us-east-1a` and `us-east-1c`. Uncordon the nodes once verified:
```bash
for node in $(kubectl get nodes -l topology.kubernetes.io/zone=us-east-1b -o jsonpath='{.items[*].metadata.name}'); do
  kubectl uncordon $node
done
```

---

## 🧪 Lab 8: Scale Applications & Simulate Traffic Spikes

In this lab, we will simulate a traffic surge to test HPA threshold scale-ups.

### Step 8.1: Port Forward target backend service
Forward request ports to reach the application locally:
```bash
kubectl port-forward service/ecom-backend-svc 8080:8080 -n production-app
```

### Step 8.2: Run ApacheBench Load Generator
Inject 10,000 HTTP requests with a concurrency factor of 50:
```bash
ab -n 10000 -c 50 http://127.0.0.1:8080/healthz
```

### Step 8.3: Monitor Scaling events
Check if HPA scales up the replicas to match the target CPU/Memory thresholds:
```bash
kubectl get hpa -n production-app --watch
```
**Expected Output:**
```text
NAME           REFERENCE                 TARGETS    MINPODS   MAXPODS   REPLICAS   AGE
ecom-backend   Deployment/ecom-backend   88%/70%    3         10        3          5m
ecom-backend   Deployment/ecom-backend   92%/70%    3         10        6          6m
```

---

## 🧪 Lab 9: Architectural Peer Review Scorecard

When evaluating a Kubernetes platform layout, SRE teams use this score template to audit designs. Apply this template to review your current architecture:

```text
========================================================================
                      PLATFORM ARCHITECTURE AUDIT
========================================================================
Category             | Safety Standard                     | Match?
------------------------------------------------------------------------
Control Plane        | Isolated etcd disk partitions       | [Yes/No]
Multi-Zone Config    | Nodes split across >=3 AZs          | [Yes/No]
Fault Isolation      | PDBs matching HPA limits            | [Yes/No]
Zero-Trust Network   | Default-Deny policies on namespaces | [Yes/No]
Observability        | Long-term Thanos metrics storage   | [Yes/No]
========================================================================
```

---

## 🧪 Lab 10: Production Readiness Assessment

Before deploying workloads to production, you must execute the Production Readiness Review (PRR) checklist.

### PRR Diagnostic Commands:
Run these diagnostics to audit pod and namespace structures:

```bash
# 1. Enforce Non-Root Execution
kubectl get pods -n production-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].securityContext.runAsNonRoot}{"\n"}{end}'

# 2. Verify Resource Request & Limit settings
kubectl get pods -n production-app -o custom-columns="NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_LIMIT:.spec.containers[*].resources.limits.memory"

# 3. Check probe statuses
kubectl get deployments -n production-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[*].livenessProbe}{"\n"}{end}'
```

If any checks return empty values, modify `production-app-tier.yaml` to ensure compliance before production promotion.
