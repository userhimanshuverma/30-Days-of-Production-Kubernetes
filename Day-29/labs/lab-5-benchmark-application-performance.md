# Lab 5: Benchmark Application Performance

In this lab, you will perform a live HTTP load test on a pod, scrape CPU throttling metrics, and locate the limit thresholds where performance degrades.

---

## 1. Deploy the Target Application
Create a deployment running a CPU-intensive endpoint:

```yaml
# performance-test-app.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fibonacci-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: fibonacci
  template:
    metadata:
      labels:
        app: fibonacci
    spec:
      containers:
      - name: app
        image: devopsinsight/fibonacci:latest # Simple app computing fibonacci values
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m # Low limit to intentionally cause throttling
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: fibonacci-service
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: fibonacci
```

Deploy the app:
```bash
kubectl apply -f performance-test-app.yaml
```

---

## 2. Execute a Vegeta Load Test
We will run a Vegeta load test at 100 RPS for 30 seconds.

```bash
# Verify Vegeta is installed or run it from a docker container inside the cluster
kubectl run vegeta --rm -i --tty --image=peterevans/vegeta -- \
  sh -c "echo 'GET http://fibonacci-service.default.svc.cluster.local/' | vegeta attack -rate=100 -duration=30s | vegeta report"
```

### Expected Vegeta Report:
```
Requests      [total, rate, throughput]  3000, 100.00, 95.50
Latencies     [min, mean, 50, 90, 95, 99, max] 15ms, 120ms, 85ms, 280ms, 450ms, 890ms, 1.5s
Success       [ratio]                    92.4%
```
*Notice the high latency values (p95 is 450ms, max is 1.5s) and the drop in success ratio.*

---

## 3. Analyze CPU Throttling Metrics
CPU throttling occurs when a container attempts to use more CPU than its limit block over a given quota period (usually 100ms).

Query the container-level throttling metrics in Prometheus:

```promql
# Percentage of CPU periods where throttling was enforced
sum(rate(container_cpu_cfs_throttled_periods_total{container="app", pod=~"fibonacci-.*"}[5m]))
/
sum(rate(container_cpu_cfs_periods_total{container="app", pod=~"fibonacci-.*"}[5m])) * 100
```

### Expected Result:
A value of **> 40%** indicates severe CPU throttling. The container is being actively restricted by the Linux kernel CFS scheduler because it exceeded the `200m` limit.

---

## 4. Tune resource limits to eliminate throttling
Now, update the deployment config. Raise the CPU limits to `1000m` (1 Core) and requests to `500m` to see the performance difference:

```yaml
        resources:
          requests:
            cpu: 500m
            memory: 256Mi
          limits:
            cpu: "1"
            memory: 512Mi
```

Apply the changes:
```bash
kubectl apply -f performance-test-app.yaml
```

---

## 5. Rerun the Vegeta Load Test
Execute the exact same Vegeta attack command:

```bash
kubectl run vegeta --rm -i --tty --image=peterevans/vegeta -- \
  sh -c "echo 'GET http://fibonacci-service.default.svc.cluster.local/' | vegeta attack -rate=100 -duration=30s | vegeta report"
```

### Expected Output after tuning:
```
Requests      [total, rate, throughput]  3000, 100.00, 100.00
Latencies     [min, mean, 50, 90, 95, 99, max] 4ms, 8ms, 6ms, 12ms, 18ms, 25ms, 40ms
Success       [ratio]                    100.0%
```
By right-sizing the CPU limits based on benchmarking data, we reduced p95 latency from **450ms to 18ms** and eliminated all timeout errors.

---

## 6. Clean up Lab
```bash
kubectl delete -f performance-test-app.yaml
```
