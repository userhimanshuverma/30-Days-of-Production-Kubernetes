# Log Lifecycle & Retention Management

This state diagram details the lifecycle of logging data as it ages, showing transitions between storage tiers to optimize costs.

```mermaid
stateDiagram-v2
    [*] --> HotPhase : Ingestion (0 - 3 Days)
    note right of HotPhase
      Stored on High-Speed SSD / Block Storage.
      Fast full-text queries, index generation.
    end note

    HotPhase --> WarmPhase : Rollover Policy (3 - 7 Days)
    note right of WarmPhase
      Indices set to read-only.
      Shards merged, moved to cheaper SSD/HDD nodes.
    end note

    WarmPhase --> ColdPhase : Index Freeze (7 - 30 Days)
    note right of ColdPhase
      Log chunks archived to cheap Object Storage (S3/GCS).
      No indexing. Slow query times, but cheap retention.
    end note

    ColdPhase --> DeletionPhase : Expiry (30+ Days)
    note right of DeletionPhase
      Logs purged.
      Compliance audits satisfied.
    end note

    DeletionPhase --> [*]
```

### Operational Lifecycle Optimization:
* **ILM (Index Lifecycle Management):** Elasticsearch automates these transitions using index templates.
* **Loki Retention Policy:** Loki uses a compactor service to scan object storage and delete chunks older than the retention limit (e.g., 30 days).
