# Incident Investigation Workflow

This flow diagram illustrates the sequential troubleshooting workflow an SRE follows to diagnose a production outage.

```mermaid
flowchart TD
    Alert[1. Alert: Payment Error Rate > 5%] --> Identify[2. Identify namespace & app targets]
    Identify --> QueryMetrics[3. Query Prometheus: check rates & latencies]
    QueryMetrics --> ExtractTrace[4. Extract transaction TraceID from request headers]
    ExtractTrace --> LogQuery[5. Search logs by TraceID: {app="payment"} |= "TraceID"]
    
    subgraph Analysis ["Log Failure Analysis"]
        LogQuery --> CheckStdout[6. Check for Exception stack traces]
        CheckStdout --> FindTimeout[7. Identify root cause: 'DB timeout connecting to SQL-Node-2']
    end

    FindTimeout --> ApplyFix[8. Apply resolution: scale connection pool / fix SQL config]
    ApplyFix --> PostMortem[9. Write Post-Mortem and update logging rules]
```

### Operational Steps:
* **Alert to Log Transition:** Avoid jumping straight to search bars without context. Start with metrics to isolate the specific namespace, time window, and pods before diving into logs.
* **Trace-based Narrowing:** Searching by transaction ID filters out unrelated logs, allowing you to trace the exact request flow.
