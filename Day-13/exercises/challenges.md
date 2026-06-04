# 🏆 Day 13 Exercises: Production Autoscaling Challenges

Test your platform engineering and troubleshooting skills by solving these real-world autoscaling scenarios.

---

## Challenge 1: Resolve HPA Thrashing (Stabilization Window Tuning)

### Scenario
A microservice named `checkout-api` is experiencing CPU oscillations under volatile traffic. Every time traffic dips for 20 seconds, the HPA terminates replicas. When the traffic returns, the remaining replicas are overwhelmed and throttled, triggering a sudden scale-up.

Below is the current HPA configuration:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: checkout-api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: checkout-api
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
```

### Task
1. Rewrite this manifest to include a customized `behavior` block.
2. Configure the HPA to scale up **instantly** (zero stabilization delay) when traffic surges.
3. Configure the HPA to wait for at least **8 minutes** (`480 seconds`) of sustained low usage before scaling down, and limit the scale-down rate to a maximum of **2 pods per minute**.

---

## Challenge 2: Calculate Prometheus Custom Metric Targets

### Scenario
You are scaling a web app based on active HTTP connections. You scrape Prometheus metrics via the Prometheus Adapter.
* Total active connections across all replicas: `450`
* Target connections per pod: `30`
* Current active replicas: `5`

### Task
Using the HPA formula, calculate the desired number of replicas:
1. Write down the HPA formula.
2. Plug in the numbers and compute the target replica count.
3. If the global tolerance is $10\%$, does this trigger a scaling action? Explain why or why not.

---

## Challenge 3: Multi-Layer Capacity Conflict Resolution

### Scenario
An SRE applies a VPA configuration to an API Deployment in `Auto` mode. The Deployment also has an HPA configured to scale on CPU utilization.
Within 10 minutes:
1. The pods start constantly restarting.
2. The HPA and VPA trigger actions concurrently.
3. The cluster runs out of capacity, leaving new replicas stuck in `Pending` state.

### Task
Explain the architectural root cause of:
1. Why HPA and VPA conflict when scaling on the same metric (CPU/Memory).
2. How you would redesign this setup to allow both resource optimization (sizing) and horizontal scaling to run safely together.
3. What steps you would take to debug the pending replicas (write the commands).
