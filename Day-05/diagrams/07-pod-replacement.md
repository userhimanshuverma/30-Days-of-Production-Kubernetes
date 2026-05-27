# 07 - Pod Replacement Flow (Graceful Termination)

This diagram details the step-by-step lifecycle flow of a Pod when it is terminated (e.g., during scale-down or rolling updates) to prevent traffic loss (achieving zero-downtime).

```mermaid
timeline
    title Pod Graceful Termination Timeline (30s Grace Period)
    00 : Pod state changed to 'Terminating' : API Server marks Pod as Terminating in etcd
    01 : API Events Dispatched : Endpoint Controller removes Pod IP from Service Endpoints list <br/> Kube-Proxy updates iptables/IPVS rules across nodes to stop routing new traffic
    02 : Kubelet Execution Start : Kubelet starts the 'preStop' hook (if defined) in parallel to Endpoint update <br/> Container continues serving existing inflight requests
    15 : Signal Delivery : preStop hook finishes <br/> Kubelet sends SIGTERM signal to container process (PID 1) <br/> Application process stops accepting new connections and begins draining active requests
    30 : Timeout Threshold : terminationGracePeriodSeconds (default: 30s) expires
    31 : Force Termination : Kubelet sends SIGKILL signal to instantly stop all remaining processes <br/> Pod is deleted from the API server
```
