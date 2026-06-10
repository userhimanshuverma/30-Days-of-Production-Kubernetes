# 🖼️ Kubernetes Production Debugging Visual Guide: 12 Diagrams

This guide contains high-resolution SRE architecture and workflow diagrams mapped using Mermaid. These diagrams serve as visual runbooks for diagnosing and operating Kubernetes clusters under production pressure.

---

## 1. Production Debugging Workflow
*The step-by-step lifecycle of an incident from automated alert firing to post-mitigation validation.*

```mermaid
graph TD
    Alert["1. Alert Fired (e.g., HTTP 5xx Spike)"] --> Triage["2. Initial Triage (Check Pod Statuses)"]
    Triage --> Inspect["3. Inspect Metadata (kubectl describe & events)"]
    Inspect --> ReadLogs["4. Read Logs (kubectl logs & trace_id correlation)"]
    ReadLogs --> Analyze{"5. Diagnose State"}
    
    Analyze -->|CrashLoopBackOff| CLB_Path["Run CrashLoop Triage"]
    Analyze -->|OOMKilled| OOM_Path["Run OOM Triage"]
    Analyze -->|Network/DNS Failure| Net_Path["Run Network/DNS Triage"]
    
    CLB_Path & OOM_Path & Net_Path --> Formulate["6. Formulate Hypothesis & Run Tests"]
    Formulate --> Fix["7. Apply Mitigation (Rollback, Resize, Config Fix)"]
    Fix --> Validate["8. Validate (Verify Metrics, Logs, & Probes)"]
    Validate --> Document["9. Incident Resolution & RCA Post-Mortem"]
```

---

## 2. CrashLoopBackOff Investigation Triage Flowchart
*How to systematic diagnose container startup and runtime crashes.*

```mermaid
graph TD
    Start["Pod status: CrashLoopBackOff"] --> CheckLogs["Check kubectl logs --previous"]
    CheckLogs --> HasLogs{Are there logs?}
    
    HasLogs -->|Yes| ParseLogs["Analyze App Stack Trace / Config Errors"]
    ParseLogs --> CheckDB{"DB / API Dependency Offline?"}
    CheckDB -->|Yes| FixDep["Fix dependency or implement connection retry backoff"]
    CheckDB -->|No| CheckConfig{"Invalid Config / Environment variables?"}
    CheckConfig -->|Yes| FixConfigMap["Fix ConfigMap / Secret mapping"]
    CheckConfig -->|No| AppBug["Investigate App Code bug"]
    
    HasLogs -->|No| CheckDescribe["Check kubectl describe pod"]
    CheckDescribe --> ExitedCode{"Inspect Exit Code"}
    ExitedCode -->|Exit Code 127| CmdError["Command/Entrypoint executable not found in image"]
    ExitedCode -->|Exit Code 137| OOM["Container OOMKilled by Cgroup limit"]
    ExitedCode -->|Exit Code 139| SegFault["Segmentation fault (C++ / Node native add-ons)"]
    ExitedCode -->|Exit Code 130/255| SigTerm["Application ignored SIGTERM and was hard killed"]
```

---

## 3. OOMKilled Analysis Flow
*Isolating memory issues between container limits and node-level pressure.*

```mermaid
graph TD
    Start["Pod Restarted / Exit Code 137"] --> InspectOOM{"Where did OOM trigger?"}
    
    InspectOOM -->|Container Cgroup Limit| CgroupOOM["Diagnostic: OOMKilled in pod description"]
    CgroupOOM --> CompareLimits["Compare Memory Usage to Cgroup Limits"]
    CompareLimits --> MemoryLeak{"Usage climbs continuously? (Staircase)"}
    MemoryLeak -->|Yes| DevLeak["Debug Application memory leak (Profiler)"]
    MemoryLeak -->|No| Sizing["Increase Cgroup memory limit (Limits/Requests)"]
    
    InspectOOM -->|Node OS Out Of Memory| NodeOOM["Diagnostic: Kernel log 'Out of memory: Killed process'"]
    NodeOOM --> CheckKubelet["Kubelet Eviction Event?"]
    CheckKubelet -->|Yes| HighUsage["Node memory exhausted. System evicted low-priority pods"]
    CheckKubelet -->|No| Unmanaged["Unmanaged process on Node host consumed all RAM"]
    HighUsage & Unmanaged --> AdjustResources["Configure Node Resource Quotas & Pod Requests"]
```

---

## 4. Network Troubleshooting Process
*Step-by-step verification of the Kubernetes data plane.*

```mermaid
flowchart TD
    Start["Pod A cannot talk to Pod B / Service"] --> CheckDNS["1. Check Name Resolution (nslookup service-name)"]
    
    CheckDNS -->|DNS Fails| ResolveDNS["Investigate CoreDNS Logs & Service definition"]
    CheckDNS -->|DNS Succeeds| CheckPing["2. Ping Pod B IP directly (from Debug Container)"]
    
    CheckPing -->|Ping Fails| CheckNetPolicy["3. Check NetworkPolicies blocking traffic"]
    CheckNetPolicy -->|Blocked| FixNetPolicy["Update NetworkPolicy ingress/egress rules"]
    CheckNetPolicy -->|Allowed| CheckCNI["Check CNI DaemonSet status & Node-to-Node routing"]
    
    CheckPing -->|Ping Succeeds| CheckCurl["4. Curl Pod B Port (curl -Iv http://pod-ip:port)"]
    CheckCurl -->|Refused| AppListen["App on Pod B not listening on port or crashed"]
    CheckCurl -->|Timeout| CheckIPTables["Check kube-proxy / iptables rules on Node"]
```

---

## 5. DNS Resolution Workflow in Kubernetes
*How an application resolves a local service DNS query inside the cluster.*

```mermaid
sequenceDiagram
    autonumber
    participant App as Pod App Container
    participant OS as OS Resolver (/etc/resolv.conf)
    participant Core as CoreDNS Service
    participant Upstream as External DNS (e.g., 8.8.8.8)

    App->>OS: Resolve "order-service"
    Note over OS: ndots: 5 (Default)<br>Appends search paths
    OS->>Core: Query "order-service.default.svc.cluster.local" (A Record)
    Core-->>OS: Return IP: 10.96.45.12 (Success)
    OS-->>App: Service IP resolved!

    Note over App: Resolving External Domain: "api.stripe.com"
    App->>OS: Resolve "api.stripe.com"
    OS->>Core: Query "api.stripe.com.default.svc.cluster.local"
    Core-->>OS: NXDOMAIN (Name Error)
    OS->>Core: Query "api.stripe.com.svc.cluster.local"
    Core-->>OS: NXDOMAIN
    OS->>Core: Query "api.stripe.com.cluster.local"
    Core-->>OS: NXDOMAIN
    OS->>Core: Query "api.stripe.com"
    Core->>Upstream: Forward Query to External Resolver
    Upstream-->>Core: Return IP: 3.18.12.4
    Core-->>OS: Return IP: 3.18.12.4
    OS-->>App: External IP resolved!
```

---

## 6. Incident Response Lifecycle
*The chronological stages of resolving a critical production issue.*

```mermaid
stateDiagram-v2
    [*] --> Detection : Automated Alert / PagerDuty
    Detection --> Triage : Establish severity, assign Incident Commander (IC)
    Triage --> Investigation : SREs debug logs, metrics, & traces
    Investigation --> Mitigation : Apply quick fix (scale up, rollback, restart)
    Mitigation --> Validation : Verify SLA restored & metrics recover
    Validation --> Resolution : Incident declared closed
    Resolution --> PostMortem : Analyze Root Cause (5 Whys)
    PostMortem --> ActionItems : Implement long-term code/config fixes
    ActionItems --> [*]
```

---

## 7. Root Cause Analysis (RCA) Decision Tree
*Isolating the root cause from a high-level system failure.*

```mermaid
graph TD
    Root["System Outage / Error Spike"] --> Config["Configuration Changes"]
    Root --> Resources["Resource Starvation"]
    Root --> Code["Application Logic Bug"]
    Root --> Infra["Infrastructure Outage"]
    
    Config --> GitOps["Recent deployments or git-commits?"]
    Config --> ConfigMaps["ConfigMap/Secret sync issues?"]
    
    Resources --> MemLimits["Cgroup Memory Limits (OOM)"]
    Resources --> CPUThrottling["CPU Starvation (Latency spike)"]
    Resources --> DiskFull["Node ephemeral storage full"]
    
    Code --> Panic["Null pointer / Exception unhandled"]
    Code --> ConnectionLeak["DB connection pool exhaustion"]
    
    Infra --> CloudAPI["Cloud provider network failure"]
    Infra --> NodeCrash["Physical node hardware failure"]
```

---

## 8. Kubernetes Debugging Toolkit
*A categorization of commands, tools, and techniques for live cluster diagnosis.*

```mermaid
graph TD
    Toolkit["Kubernetes Debugging Toolkit"] --> CLI["kubectl CLI Core Commands"]
    Toolkit --> ExtTools["SRE Open Source Utilities"]
    Toolkit --> Diagnostics["Live Diagnostics Tech"]
    
    CLI --> CLI_Status["kubectl get, describe, events"]
    CLI --> CLI_Logs["kubectl logs --previous -f -l app=foo"]
    CLI --> CLI_Inspect["kubectl exec, port-forward"]
    
    ExtTools --> Stern["Stern (Multi-pod log tailing)"]
    ExtTools --> K9s["K9s (Terminal Console UI)"]
    ExtTools --> Netshoot["Netshoot (Diagnostic Pod Container)"]
    
    Diagnostics --> Ephemeral["Ephemeral Debug Containers (kubectl debug)"]
    Diagnostics --> TCPDump["Packet Capture (tcpdump / Wireshark)"]
```

---

## 9. Service Failure Investigation Path
*Finding out why a Kubernetes Service is failing to route requests.*

```mermaid
graph TD
    Start["Service returns 503 / Connection Refused"] --> CheckEndpoints["Run: kubectl get endpoints service-name"]
    CheckEndpoints --> HasEndpoints{Are endpoints listed?}
    
    HasEndpoints -->|No| CheckSelectors["Check labels on pods vs service spec selector"]
    CheckSelectors --> Match{"Do labels match?"}
    Match -->|No| FixLabels["Correct Service selector or Pod labels"]
    Match -->|Yes| CheckPodState["Check Pod statuses (Running vs Pending/Crashed)"]
    
    HasEndpoints -->|Yes| CheckTargetPort["Verify targetPort matches container port"]
    CheckTargetPort --> PortMatch{"Ports aligned?"}
    PortMatch -->|No| FixPort["Correct targetPort in Service manifest"]
    PortMatch -->|Yes| CheckKubeProxy["Check kube-proxy DaemonSet pods & node IP routing"]
```

---

## 10. Production Incident Workflow
*The coordination path between the On-Call Engineer, Team, and Stakeholders.*

```mermaid
sequenceDiagram
    autonumber
    actor OnCall as On-Call Engineer
    participant Alert as Monitoring (Prometheus/PagerDuty)
    participant WarRoom as incident-slack-channel
    participant Team as SRE Team / Devs
    participant Stakeholder as Product / Management

    Alert->>OnCall: Alert triggered: checkout-latency > 2s
    OnCall->>WarRoom: Declare Incident, create Google Meet / Slack War Room
    OnCall->>Stakeholder: Send initial status update (Investigating)
    OnCall->>Team: Page secondary on-call / backend leads
    Team->>WarRoom: Join war room, coordinate troubleshooting
    Note over Team, OnCall: Triage: OOMKilled payment pods discovered
    OnCall->>WarRoom: Mitigate: Scale up limits + replicas
    OnCall-->>Alert: Alert clears
    OnCall->>Stakeholder: Send resolution update (Services Healthy, SLA restored)
    OnCall->>WarRoom: Schedule Post-Mortem review
```

---

## 11. Troubleshooting Decision Matrix
*A high-level logical path from Pod phases to specific diagnostic playbooks.*

```mermaid
graph TD
    PodStatus["Analyze kubectl get pods state"] --> Pending["Phase: Pending"]
    PodStatus --> Running["Phase: Running (But failing)"]
    PodStatus --> Failed["Phase: Failed / CrashLoop"]
    
    Pending --> Scheduler["Diagnostic: Scheduler cannot place pod"]
    Scheduler --> CheckLimits["Check node resource capacity & taints/tolerations"]
    
    Running --> HealthChecks["Diagnostic: Liveness/Readiness probe failing"]
    HealthChecks --> CheckEndpointsLogs["Check probe path, timeout duration, and HTTP logs"]
    
    Failed --> StartupCheck["Diagnostic: Process exited immediately"]
    Failed --> InspectExitCodes["Analyze container exit codes and logs --previous"]
```

---

## 12. End-to-End Debugging Architecture
*The complete logical architecture mapping a user connection down through the control plane to the data plane.*

```mermaid
graph TD
    subgraph "External Ingress Layer"
        User["User Browser"] -->|HTTPS| Ingress["Ingress Controller Pod"]
    end

    subgraph "Control Plane Node"
        KubeAPI["kube-apiserver"]
        KubeEvents["Cluster Event Stream"]
        KubeAPI <--> KubeEvents
    end

    subgraph "Data Plane Nodes (Worker)"
        Ingress -->|Route request| Svc["Kubernetes Service (ClusterIP)"]
        Svc -->|Load Balances (iptables/IPVS)| PodA["Pod A (Frontend Container)"]
        PodA -->|DNS Resolve| CoreDNS["CoreDNS Pods"]
        PodA -->|Route API request| PodB["Pod B (Payment Container)"]
        
        Kubelet["kubelet daemon"] -->|Checks container health| PodA & PodB
        Kubelet -->|Logs events| KubeAPI
    end
    
    subgraph "SRE Diagnostic Actions"
        SRE["SRE Laptop"] -->|kubectl describe/logs| KubeAPI
        SRE -->|kubectl debug ephemeral| PodB
        SRE -->|kubectl port-forward| PodA
    end
```

---

*Proceed to the [notes/](../notes/) folder to read the SRE Core Concepts Guide detailing the inner workings of these components.*
