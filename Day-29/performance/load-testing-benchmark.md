# 📈 Load Testing & Capacity Benchmarking Playbook

This document details how to execute load tests on Kubernetes pods to discover their maximum physical limits, find performance degradation inflection points (the "knee-point"), and calculate resource requirements based on metrics.

---

## 1. Finding the Performance "Knee-Point"

Blindly setting CPU and memory limits without load testing leads to either:
1. **Underprovisioning**: Frequent CPU throttling (latency spikes) or OOMKills.
2. **Overprovisioning**: High costs and underutilized cluster nodes.

The goal of capacity benchmarking is to find the **performance knee-point** (the threshold where throughput plateaus and latency starts growing exponentially).

```
Latency
  ▲
  │                                     / (System saturated: throttling/waiting)
  │                                    /
  │                                   /
  │                                  /
  │    _____________________________/ (The Knee-Point: optimal requests configuration)
  │   /
  │  /
  └─────────────────────────────────────────► Throughput (RPS)
```

---

## 2. Load Testing Tools

We use two primary open-source performance tools:
1. **k6**: Excellent for complex scripting, user flows, and modern API protocols.
2. **Vegeta**: Extremely effective for constant rate HTTP load testing.

### Tool 1: Running a Vegeta Constant Rate Test
Deploy Vegeta inside the cluster (to test pods directly and bypass external load balancer overhead) or run it locally:

```bash
# Run a test targeting the pod service at 500 Requests Per Second (RPS) for 60 seconds
echo "GET http://my-service.default.svc.cluster.local/api/v1/data" | \
  vegeta attack -rate=500 -duration=60s | \
  vegeta report
```

#### Sample Vegeta Report Analysis:
```
Requests      [total, rate, throughput]  30000, 500.00, 498.90
Duration      [total, attack, wait]      1m0s, 60s, 110ms
Latencies     [min, mean, 50, 90, 95, 99, max] 12ms, 25ms, 15ms, 45ms, 90ms, 250ms, 1.2s
Success       [ratio]                    99.8%
Status Codes  [code:count]               200:29940  504:60
```
*   **Analysis**: Latencies look good up to p90, but p99 is 250ms and we have 60 timeout responses (504s). This indicates the container is beginning to throttle.

---

## 3. Step-by-Step Benchmarking Methodology

To benchmark an application deployment, follow this workflow:

### Step 1: Set CPU Limits to Infinite (No CPU Limit)
To find the raw potential of the container without artificial kernel throttling, set requests (e.g., `200m`) but omit the limits parameter.

### Step 2: Ramp Up Traffic incrementally
Run sequential load tests at increasing concurrency/RPS levels:
*   Test 1: 50 RPS
*   Test 2: 100 RPS
*   Test 3: 200 RPS
*   Test 4: 400 RPS
*   Test 5: 800 RPS

### Step 3: Scrape Container Metrics during the test
Run the following Prometheus queries to find the resource consumption at each stage:

```promql
# CPU usage in cores
sum(rate(container_cpu_usage_seconds_total{container="my-app"}[1m])) by (pod)

# Memory RSS (Actual resident memory)
sum(container_memory_rss{container="my-app"}) by (pod)
```

### Step 4: Map RPS to CPU/Memory usage
Build a table to locate the saturation point:

| Target RPS | Latency (p95) | Latency (p99) | CPU Usage (Cores) | Memory (RSS) | Error Rate |
|---|---|---|---|---|---|
| 50 | 8ms | 12ms | 0.08 Cores | 180 MiB | 0% |
| 100 | 9ms | 15ms | 0.15 Cores | 182 MiB | 0% |
| 200 | 11ms | 20ms | 0.28 Cores | 190 MiB | 0% |
| 400 | 15ms | 32ms | 0.52 Cores | 210 MiB | 0% |
| **600 (Knee-point)** | **22ms** | **55ms** | **0.78 Cores** | **230 MiB** | **0%** |
| 800 (Saturated) | 98ms | 450ms | 0.95 Cores | 240 MiB | 3.5% (504 Errors) |

---

## 4. Calculating Production Requests and Limits

Based on the 600 RPS "knee-point" determined above, here is how we size our production spec:

### A. Sizing CPU Requests
Set requests to the CPU usage of the knee-point:
*   **CPU Request**: `800m` (Ensure the scheduler guarantees this baseline so the container always performs well at its sweet spot).

### B. Sizing CPU Limits
Set limits to prevent a single pod from monopolizing the node, but high enough to handle micro-bursts of traffic:
*   **CPU Limit**: `1200m` (1.5x of CPU Requests. This prevents heavy throttling during short duration surges, but protects other workloads on the node).

### C. Sizing Memory Requests and Limits
Memory is a non-compressible resource. Unlike CPU (which is throttled), if a container requests less memory than it consumes, the OS can run out of RAM, leading to kernel eviction or **OOMKill**.
*   **Memory Request**: Set to the maximum observed RAM usage at knee-point + 30% safety buffer.
    *   `230MiB * 1.30` = `300MiB`
*   **Memory Limit**: Set to 1.5x - 2x of requests to handle memory fragmentation/leaks without crash looping.
    *   `300MiB * 1.5` = `450MiB`
