# EFK Logging Stack Architecture

This diagram details the full-text search layout of the EFK stack. It illustrates how log streams are indexed and searched using shards and replicas.

```mermaid
flowchart TD
    subgraph Nodes ["Kubernetes Nodes"]
        Fb1[Fluent Bit DaemonSet]
        Fb2[Fluent Bit DaemonSet]
    end

    subgraph Elasticsearch ["Elasticsearch Cluster"]
        Node1[Master Node]
        
        subgraph DataNode1 ["Data Node 1"]
            Shard1[(Primary Shard 0)]
            Shard2[(Replica Shard 1)]
        end
        
        subgraph DataNode2 ["Data Node 2"]
            Shard3[(Primary Shard 1)]
            Shard4[(Replica Shard 0)]
        end
    end

    subgraph Visualization ["Visualization Layer"]
        Kibana[Kibana UI Dashboard]
    end

    Fb1 -->|REST Bulk API JSON| DataNode1
    Fb2 -->|REST Bulk API JSON| DataNode2
    
    Kibana -->|Search Queries| Node1
    Node1 -->|Scatter-Gather Search| DataNode1
    Node1 -->|Scatter-Gather Search| DataNode2
```

### Architectural Details:
* **Bulk Ingestion:** Fluent Bit bundles logs into JSON packages and writes them using the Elasticsearch bulk HTTP API (`_bulk`) to minimize network connections.
* **Master vs. Data Nodes:** Master nodes manage index mappings and cluster state. Data nodes hold index shards and execute writes and search lookups.
* **Sharding & Replicas:** Primary shards split indices for horizontal scaling, while replica shards sit on separate nodes to provide high availability and balance read traffic.
