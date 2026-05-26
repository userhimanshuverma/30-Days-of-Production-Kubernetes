# 📊 Pod Architecture & Lifecycle Diagrams
## 30 Days of Production Kubernetes — Day 4

This document contains 12 high-resolution, production-grade Mermaid diagrams that map the internal architecture, network namespaces, lifecycle, and communication patterns of Kubernetes Pods.

---

### 1. Pod Internals & Namespace Architecture
This diagram illustrates the underlying structure of a Pod on a node. The **Pause Container** is created first, holding open the shared namespaces (Network, IPC, UTS), which the actual application containers then join.

```mermaid
graph TB
    subgraph "Kubernetes Pod Boundary (Cgroup + Namespaces)"
        direction TB
        pause["Pause Container<br/>(holds namespaces: net, ipc, uts, pid)"]
        
        subgraph "Shared Namespaces"
            net["Network Namespace<br/>(Shared IP, Loopback veth)"]
            ipc["IPC Namespace<br/>(Shared POSIX Message Queues)"]
            uts["UTS Namespace<br/>(Shared Hostname)"]
        end

        subgraph "Application Containers"
            app["App Container A<br/>(nginx)"]
            appB["App Container B<br/>(helper)"]
        end

        pause --> net
        pause --> ipc
        pause --> uts

        app -.-> net
        app -.-> ipc
        appB -.-> net
        appB -.-> ipc
    end

    host_net["Host Network Interface (eth0)"] <--> net

    style pause fill:#4b0082,stroke:#fff,stroke-width:2px,color:#fff
    style net fill:#8a2be2,stroke:#fff,stroke-width:1px,color:#fff
    style ipc fill:#8a2be2,stroke:#fff,stroke-width:1px,color:#fff
    style uts fill:#8a2be2,stroke:#fff,stroke-width:1px,color:#fff
    style app fill:#1e90ff,stroke:#fff,stroke-width:1px,color:#fff
    style appB fill:#20b2aa,stroke:#fff,stroke-width:1px,color:#fff
```

---

### 2. Multi-Container Pod Architecture
Shows the boundary of a multi-container Pod, highlighting how containers run in isolated cgroups but share namespaces and volumes.

```mermaid
graph LR
    subgraph "Pod Boundary"
        subgraph "cgroup-limits-container-1"
            c1["App Container<br/>(NodeJS API)"]
        end
        subgraph "cgroup-limits-container-2"
            c2["Sidecar Container<br/>(Log Shipper)"]
        end
        vol[("Shared Volume<br/>(emptyDir)")]
        c1 -- "Writes Logs" --> vol
        c2 -- "Reads Logs" --> vol
        c1 -- "Localhost:8080" --> c2
    end
    
    style c1 fill:#1e90ff,stroke:#fff,stroke-width:1px,color:#fff
    style c2 fill:#20b2aa,stroke:#fff,stroke-width:1px,color:#fff
    style vol fill:#483d8b,stroke:#fff,stroke-width:1px,color:#fff
```

---

### 3. Init Container Execution Flow
Init containers execute sequentially. If any init container fails, the Pod is restarted (depending on the `restartPolicy`) and subsequent containers do not start.

```mermaid
flowchart TD
    Start([Pod Scheduled to Node]) --> Init1[Start Init Container 1]
    Init1 --> Check1{Exit Code = 0?}
    Check1 -- Yes --> Init2[Start Init Container 2]
    Check1 -- No --> Fail[Evaluate restartPolicy]
    Init2 --> Check2{Exit Code = 0?}
    Check2 -- Yes --> StartApp[Start Main Containers & Native Sidecars]
    Check2 -- No --> Fail
    Fail -- Restart --> Init1
    Fail -- Stop/Fail --> PodFail([Pod Failed State])
    
    style Start fill:#4b0082,stroke:#fff,stroke-width:1px,color:#fff
    style Init1 fill:#8a2be2,stroke:#fff,stroke-width:1px,color:#fff
    style Init2 fill:#8a2be2,stroke:#fff,stroke-width:1px,color:#fff
    style StartApp fill:#1e90ff,stroke:#fff,stroke-width:2px,color:#fff
    style PodFail fill:#b22222,stroke:#fff,stroke-width:1px,color:#fff
```

---

### 4. Sidecar Communication (Localhost Loopback)
Demonstrates how sidecars and main containers communicate inside the shared network namespace over localhost, avoiding external network hops.

```mermaid
sequenceDiagram
    autonumber
    participant Client as External Client
    participant Proxy as Sidecar Proxy (e.g. Envoy)
    participant App as Main App Container
    
    Client->>Proxy: GET /api/v1/resource (port 80)
    Note over Proxy: Validate token & check cache
    Proxy->>App: Forward Request (localhost:8080)
    App-->>Proxy: Return JSON Response
    Proxy-->>Client: HTTP 200 OK (Enriched)
```

---

### 5. Pod Lifecycle States
Shows the complete phase diagram of a Pod from deployment submission to terminal state.

```mermaid
stateDiagram-v2
    [*] --> Pending : Pod Scheduled / Image Pulling
    Pending --> Running : All Containers Started
    Pending --> Failed : Init Container Crashes / Policy Reject
    Running --> Succeeded : Jobs finished (Exit 0)
    Running --> Failed : App Crashed (Exit != 0) / Evicted
    Running --> Unknown : Kubelet loses heartbeat
    Unknown --> Pending : Node recovers or rescheduled
    Succeeded --> [*]
    Failed --> [*]
```

---

### 6. Shared Network Namespace Internals
Visualizes how the CNI plugin creates a virtual ethernet pair (`veth`), attaching one end to the host bridge and the other to the Pod namespace, which is then shared among all containers.

```mermaid
graph LR
    subgraph "Linux Host Network Namespace"
        cbr0["Bridge (cbr0 / flannel / calico)"]
        veth_host["Virtual Interface (veth-host)"]
        cbr0 <--> veth_host
        
        subgraph "Pod Network Namespace"
            veth_pod["Pod Interface (eth0)"]
            lo["Loopback Interface (lo)"]
            
            subgraph "Container A (App)"
                p1["Port 8080"]
            end
            
            subgraph "Container B (Sidecar)"
                p2["Port 9090"]
            end
        end
        veth_host <--> veth_pod
        p1 <--> lo
        p2 <--> lo
    end
    
    style cbr0 fill:#483d8b,stroke:#fff,color:#fff
    style veth_host fill:#4b0082,stroke:#fff,color:#fff
    style veth_pod fill:#8a2be2,stroke:#fff,color:#fff
    style lo fill:#8a2be2,stroke:#fff,color:#fff
```

---

### 7. Shared Storage Volumes Mechanics
Details how the kubelet mounts host paths or remote PVs onto the host filesystem under `/var/lib/kubelet/pods/<pod-uid>/volumes/` and binds them into the individual container container-mount-namespaces.

```mermaid
graph TD
    subgraph "Linux Host"
        pv[("Persistent Volume / hostPath")]
        subgraph "kubelet mount directory"
            pod_vol["/var/lib/kubelet/pods/&lt;pod-uid&gt;/volumes/kubernetes.io~empty-dir/logs/"]
        end
        pv --> pod_vol

        subgraph "Container A Mount Namespace"
            path1["/usr/share/nginx/html/logs/"]
        end

        subgraph "Container B Mount Namespace"
            path2["/var/log/app/"]
        end

        pod_vol -- "Bind Mount" --> path1
        pod_vol -- "Bind Mount" --> path2
    end
    
    style pv fill:#483d8b,stroke:#fff,color:#fff
    style pod_vol fill:#8a2be2,stroke:#fff,color:#fff
    style path1 fill:#1e90ff,stroke:#fff,color:#fff
    style path2 fill:#20b2aa,stroke:#fff,color:#fff
```

---

### 8. Pod Startup Sequence
The chronological bootstrap timeline of a Pod on a worker node.

```mermaid
sequenceDiagram
    autonumber
    participant K as kubelet
    participant CRI as containerd (CRI)
    participant CNI as Cilium/Calico (CNI)
    participant CSI as Storage CSI
    
    K->>CRI: Create Pod Sandbox (Pause container)
    CRI->>CNI: Setup Pod Network (Assign IP, setup veth)
    CNI-->>CRI: Network ready
    K->>CSI: NodeStageVolume & NodePublishVolume
    CSI-->>K: Volume mounted
    K->>CRI: Pull & Start Init Containers (Sequential)
    CRI-->>K: Init Containers finished
    K->>CRI: Pull & Start Native Sidecars (restartPolicy: Always)
    K->>CRI: Pull & Start Main Containers
    K->>K: Run Startup, Liveness & Readiness Probes
```

---

### 9. Probe Lifecycle Execution
Visualizes how the kubelet periodically probes the container, transitioning from startup to steady-state checks.

```mermaid
flowchart TD
    Start([Container Started]) --> Startup{Startup Probe Configured?}
    Startup -- Yes --> RunStartup[Execute Startup Probe]
    RunStartup --> CheckStartup{Successful?}
    CheckStartup -- No --> FailStartup[Fail Count >= Threshold?]
    FailStartup -- Yes --> RestartContainer[Restart Container]
    FailStartup -- No --> RunStartup
    CheckStartup -- Yes --> ReadyLoop
    
    Startup -- No --> ReadyLoop[Start Liveness & Readiness Loop]
    
    subgraph "Parallel Evaluation"
        direction TB
        subgraph "Liveness Check"
            L1[Run Liveness Probe] --> L2{Healthy?}
            L2 -- No --> L3[Fail Count >= Threshold?]
            L3 -- Yes --> RestartContainer
            L3 -- No --> L1
            L2 -- Yes --> L1
        end

        subgraph "Readiness Check"
            R1[Run Readiness Probe] --> R2{Healthy?}
            R2 -- No --> R3[Remove from Service Endpoint]
            R3 --> R1
            R2 -- Yes --> R4[Add to Service Endpoint]
            R4 --> R1
        end
    end
    
    style Start fill:#4b0082,stroke:#fff,color:#fff
    style RestartContainer fill:#b22222,stroke:#fff,color:#fff
```

---

### 10. Container Restart Policy Flow
Kubelet evaluates the exit code of containers and decides whether to restart them, applying exponential backoff delay scaling.

```mermaid
flowchart TD
    Exit([Container Exited]) --> Code{Exit Code = 0?}
    
    Code -- Yes --> Succeeded{RestartPolicy?}
    Code -- No --> Failed{RestartPolicy?}
    
    Succeeded -- Always --> Backoff[Calculate Exponential Backoff Delay<br/>10s, 20s, 40s ... max 300s]
    Succeeded -- OnFailure --> Terminate[Keep in Completed State]
    Succeeded -- Never --> Terminate
    
    Failed -- Always --> Backoff
    Failed -- OnFailure --> Backoff
    Failed -- Never --> Terminate
    
    Backoff --> Sleep[Wait for Backoff Duration]
    Sleep --> Restart[Recreate and Launch Container]
    
    style Exit fill:#4b0082,stroke:#fff,color:#fff
    style Restart fill:#1e90ff,stroke:#fff,color:#fff
    style Terminate fill:#483d8b,stroke:#fff,color:#fff
```

---

### 11. Service Mesh Sidecar Interception
How iptables rules inside the Pod Network Namespace redirect incoming and outgoing traffic into the sidecar proxy (e.g. Envoy).

```mermaid
graph TD
    Client["External Service Client"]
    
    subgraph "Service Mesh Pod Network Namespace"
        iptables_in["PREROUTING<br/>(iptables redirect)"]
        envoy["Envoy Proxy Container<br/>(Port 15001/15006)"]
        app["App Container<br/>(Port 8080)"]
        iptables_out["OUTPUT<br/>(iptables redirect)"]
        
        iptables_in -- "Redirect to port 15006" --> envoy
        envoy -- "Forwarded local request" --> app
        app -- "Outgoing request" --> iptables_out
        iptables_out -- "Redirect to port 15001" --> envoy
    end
    
    Client --> iptables_in
    envoy --> ExternalDest["External Destination Service"]
    
    style envoy fill:#20b2aa,stroke:#fff,color:#fff
    style app fill:#1e90ff,stroke:#fff,color:#fff
```

---

### 12. Real Production Multi-Container Pod Example
A production deployment with an init container, a main web server, a native vault-agent sidecar, and a legacy logging daemon.

```mermaid
graph TB
    subgraph "Production Pod Boundary"
        subgraph "Init Stage"
            init["init-schema<br/>(Database Migration Run)"]
        end
        
        subgraph "Running Stage"
            app["main-api-server<br/>(Flask App)"]
            vault["vault-agent<br/>(Native Sidecar: token renewer)"]
            fluent["fluent-bit<br/>(Logging Sidecar)"]
        end

        shared_vol[("Shared Temp Volume")]
        secrets_vol[("Shared Secret Volume")]

        init -- "Exits 0" --> RunningStage
        vault -- "Writes tokens" --> secrets_vol
        app -- "Reads tokens" --> secrets_vol
        app -- "Writes JSON logs" --> shared_vol
        fluent -- "Tail and uploads logs" --> shared_vol
    end

    style init fill:#8a2be2,stroke:#fff,color:#fff
    style app fill:#1e90ff,stroke:#fff,color:#fff
    style vault fill:#20b2aa,stroke:#fff,color:#fff
    style fluent fill:#20b2aa,stroke:#fff,color:#fff
```
