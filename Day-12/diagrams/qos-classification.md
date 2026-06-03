# 🏷️ QoS Classification Flowchart

This decision tree shows the exact classification flow used by Kubelet to determine the Quality of Service (QoS) class of a Pod.

```mermaid
graph TD
    Start["New Pod Manifest Evaluated"] --> CheckReqLim{"Are Requests & Limits<br/>configured for all containers?"}
    
    CheckReqLim -- "Yes" --> CheckEqual{"Do CPU & Memory<br/>Requests equal Limits?"}
    CheckReqLim -- "No" --> CheckAnyReq{"Is there any CPU or Memory<br/>Request configured?"}

    CheckEqual -- "Yes (Requests == Limits)" --> Guaranteed["Guaranteed QoS<br/>(oom_score_adj: -997)"]
    CheckEqual -- "No (Requests != Limits)" --> Burstable["Burstable QoS<br/>(oom_score_adj: 2 to 999)"]

    CheckAnyReq -- "Yes" --> Burstable
    CheckAnyReq -- "No" --> BestEffort["BestEffort QoS<br/>(oom_score_adj: 1000)"]

    style Guaranteed fill:#28A745,stroke:#333,stroke-width:2px,color:#fff
    style Burstable fill:#FFC107,stroke:#333,stroke-width:2px,color:#333
    style BestEffort fill:#DC3545,stroke:#333,stroke-width:2px,color:#fff
```

### Explanatory Summary
- **Guaranteed:** Lowest eviction risk. All containers must specify CPU and Memory requests and limits, and they must be equal.
- **Burstable:** Medium eviction risk. At least one container specifies a CPU or Memory request, and they do not match limits (allows bursting above requests).
- **BestEffort:** Highest eviction risk. No resource requests or limits are set in the Pod. These Pods are evicted first under resource pressure.
