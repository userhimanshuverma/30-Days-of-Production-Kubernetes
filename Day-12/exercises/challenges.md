# 🏆 Daily Assignment: Resource Management & Scheduling Challenges

Complete the following real-world challenges to test your understanding of Kubernetes resource allocation and scheduling.

---

## Challenge 1: Resolve a Fragmented Cluster (Cost Optimization)

### Scenario
You have a cluster of 3 nodes, each with `4 CPU` and `8Gi` of memory.
The cluster currently has the following Pods scheduled:
- Node 1: Pod-A (Request: `3 CPU`, `2Gi` Mem)
- Node 2: Pod-B (Request: `3 CPU`, `2Gi` Mem)
- Node 3: Pod-C (Request: `3 CPU`, `2Gi` Mem)

You need to schedule a critical API deployment with 2 replicas, each requesting `2 CPU` and `4Gi` of memory.

### Tasks
1. Explain why the new API replicas cannot schedule under the current configuration, despite the cluster having a total of `3 CPU` and `18Gi` of free resources in aggregate.
2. Propose an optimization strategy to accommodate the new Pods without adding a new node.
3. Write a deployment manifest for the API workloads using node selector or pod affinity rules that ensures optimal placement.

---

## Challenge 2: Design a Sizing Policy for a Latency-Sensitive API

### Scenario
You are onboarding a high-traffic HTTP checkout service. It has the following profile:
- Average CPU utilization: `200m`
- Traffic peaks (traffic doubles in seconds): CPU usage spikes to `1.5 Cores`
- Memory working set: `400Mi` (steady state, no memory leaks)
- Under CPU limits of `500m`, the service experiences high p99 latency (exceeding 200ms).

### Tasks
1. Define the ideal `resources` block (requests and limits) for this service to ensure latency stays low during traffic spikes, while protecting the node.
2. Explain the QoS classification this config results in.
3. Justify your choice of requests and limits based on CFS throttling mechanics.

---

## Challenge 3: Debug a Multi-Tenant Scheduling Hang

### Scenario
A developer applied the following YAML in their namespace but the Pod remains `Pending`:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: batch-job
  namespace: team-beta
spec:
  containers:
  - name: runner
    image: alpine:latest
    command: ["sleep", "60"]
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
```
The node has `2 CPU` and `4Gi` of memory free.

### Tasks
1. Identify potential reasons why this Pod is pending.
2. Write down the sequence of `kubectl` commands you would execute to diagnose the issue.
3. If a namespace **LimitRange** is active with `defaultRequest: cpu: "3"`, explain how this changes the scheduling outcome.
