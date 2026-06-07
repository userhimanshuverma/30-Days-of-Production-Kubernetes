# Grafana Loki Architecture

This diagram shows Loki's write and read paths. It highlights how write streams bypass indexing for raw content, while the read path queries chunk indexes and parses raw streams.

```mermaid
flowchart TD
    %% Clients
    Shipper[Fluent Bit / Promtail] -->|HTTP POST JSON/Protobuf| Dist[Distributor]
    
    %% Write Path
    subgraph Ingestion ["Loki Write Path"]
        Dist -->|Consistent Hashing| Ing1[Ingester 1]
        Dist -->|Consistent Hashing| Ing2[Ingester 2]
    end
    
    %% Storage Backends
    subgraph Storage ["Persistent Storage"]
        IndexDB[(Metadata Index Database<br/>BoltDB / Loki DB)]
        ObjectStore[(Object Storage Chunks<br/>S3 / MinIO / GCS)]
    end
    
    Ing1 -->|Flushes Index| IndexDB
    Ing1 -->|Flushes Chunks| ObjectStore
    Ing2 -->|Flushes Index| IndexDB
    Ing2 -->|Flushes Chunks| ObjectStore

    %% Read Path
    subgraph Querying ["Loki Read Path"]
        User[Grafana / Developer CLI] -->|LogQL Request| Querier[Loki Querier]
        Querier -->|Queries Label Index| IndexDB
        Querier -->|Fetches Raw Chunks| ObjectStore
        Querier -->|Scans & Filters in Parallel| Querier
    end
```

### Components Summary:
* **Distributor:** Validates incoming streams, checks ingestion rate limits, and uses consistent hashing to assign streams to Ingesters.
* **Ingester:** Buffers incoming log lines in memory, groups them into chunks, and periodically flushes compressed logs to object storage.
* **Querier:** Handles LogQL execution by fetching index metadata to discover relevant chunks, retrieving the chunks from object storage, and scanning lines in parallel.
