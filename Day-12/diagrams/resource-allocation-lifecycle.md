# 🔄 Resource Allocation Lifecycle

This state diagram visualizes the timeline of resource reservation, consumption, and release.

```mermaid
stateDiagram-v2
    [*] --> Submitted : Pod Spec Applied
    
    state Submitted {
        [*] --> Unscheduled : Wait in Scheduling Queue
        Unscheduled --> ResourceCheck : Scheduler evaluates Node Allocatable
    }

    state ResourceCheck {
        [*] --> Filtered : Node has enough capacity (Requests)
        Filtered --> Reserved : Optimistic Binding written to cache
    }

    state Execution {
        [*] --> CgroupsCreated : Kubelet configures host cgroups
        CgroupsCreated --> ContainerRunning : Resource limits applied (quota & memory max)
        ContainerRunning --> Bursting : CPU/Mem exceeds request but below limit
        Bursting --> Throttling : CPU exceeds limit (CFS blocks runtime)
        Bursting --> TerminatedOOM : Memory exceeds limit (OOM Killer SIGKILL)
    }

    Reserved --> Execution : Binding success, Kubelet boots Pod
    Execution --> Released : Pod terminates normally or is deleted
    TerminatedOOM --> Released : Pod killed & resources freed
    Released --> [*] : Scheduler Cache & Node Capacity updated
```

### Explanatory Summary
1. **Unscheduled:** Pod requests are analyzed against the node allocation pools.
2. **Reserved:** The scheduler performs an optimistic booking in its local cache.
3. **Execution:** Cgroups are established on the target host by the Kubelet.
4. **Compression / Termination:** CPU limits trigger throttling; memory limits trigger OOM terminations.
5. **Released:** Upon Pod deletion or termination, the resource allocation ledger is updated to make space for future pods.
