# 💀 OOMKilled Workflow

This workflow diagram illustrates how the Linux Out-Of-Memory (OOM) Killer reacts when a container exceeds its memory limit or when the host runs out of memory.

```mermaid
graph TD
    Start["Container allocations increase memory consumption"] --> CheckLimit{"Has container hit its Memory Limit?"}
    
    CheckLimit -- "Yes" --> ContainerOOM["Trigger Cgroup OOM Killer"]
    CheckLimit -- "No" --> CheckHostMemory{"Is Node Host memory exhausted?"}

    CheckHostMemory -- "Yes" --> HostOOM["Trigger System OOM Killer"]
    CheckHostMemory -- "No" --> Normal["Execution continues normally"]

    ContainerOOM --> ScanCgroup["Scan processes inside container's Cgroup"]
    HostOOM --> ScanSystem["Scan all processes on the host node"]

    ScanCgroup --> CalcScore["Determine oom_score for each process<br/>(Calculated based on memory % + oom_score_adj)"]
    ScanSystem --> CalcScore

    CalcScore --> SelectMax["Select process with highest oom_score"]
    SelectMax --> SIGKILL["Send SIGKILL (Exit Code 137) to process"]
    
    SIGKILL --> TerminateContainer["Container process terminated"]
    TerminateContainer --> UpdateKubelet["Kubelet detects exit, marks Pod status: OOMKilled"]
    UpdateKubelet --> RestartPolicy["Apply RestartPolicy (Restart container or fail Pod)"]

    style ContainerOOM fill:#DC3545,stroke:#333,color:#fff
    style HostOOM fill:#721C24,stroke:#333,color:#fff
    style SIGKILL fill:#DC3545,stroke:#333,color:#fff
```

### Explanatory Summary
- **Cgroup OOM:** Isolated to the container. Only container processes are evaluated, and the container is killed. This is caused by setting limits too low.
- **System OOM:** The entire host is exhausted. The Linux kernel scans the whole node. Due to Kubelet settings, `BestEffort` and `Burstable` container processes have high `oom_score` values, making them the primary targets to save the host.
- **Exit Code 137:** Indicates termination by signal `9` (`SIGKILL` -> $128 + 9 = 137$).
