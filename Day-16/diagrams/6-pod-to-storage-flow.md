# Pod-to-Storage Log Packet Flow

This block diagram traces a log record's lifecycle, showing how it transforms from a plain text line in memory to an indexed log entry.

```mermaid
flowchart TD
    App[1. App Log: Print Line] -->|stdout stream| CRI[2. CRI Wrapper Appended]
    CRI -->|Written to host| Disk[3. Node Host Disk Cache]
    Disk -->|Read by agent| Agent[4. Log Processor Agent]
    
    subgraph Processing ["Log Processor Agent Pipeline"]
        Agent --> Parse[5. Text to JSON Map]
        Parse --> Filter[6. Inject Kubernetes Metadata]
        Filter --> Mask[7. Mask Sensitive Fields]
        Mask --> Buffer[8. Buffer to Disk/RAM]
    end

    Buffer -->|REST Post Batch| Network[9. Network Ingress / Load Balancer]
    Network --> DB[10. Storage Database]
    
    subgraph Storage ["Backend Database Storage"]
        DB --> Index[11. Save Index]
        DB --> StoragePersist[12. Compress & Save Logs]
    end
```

### Storage Stages:
* **Log Lines to JSON:** Converting flat strings to structural fields allows indices to reference specific elements (e.g. `service_name`).
* **Enrichment:** Metadata injection guarantees that logs can be queried by resource properties (namespace, labels, annotations) even after the target pod has been terminated.
