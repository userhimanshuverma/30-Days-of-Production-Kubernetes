# 📐 Node Scaling Lifecycle

This diagram shows the states a node transitions through from provisioning in the cloud to decommissioning.

```mermaid
stateDiagram-v2
    [*] --> ProvTriggered : Pending Pod Found
    ProvTriggered --> VMProvisioning : Cloud API Call
    VMProvisioning --> CloudBootstrapping : OS Boot / Kubelet Installer
    CloudBootstrapping --> Registering : API Join request
    Registering --> ActiveSchedulable : Mark Node 'Ready'
    
    ActiveSchedulable --> Cordoned : Under-utilization < 50% (Scale Down)
    Cordoned --> Draining : Pods rescheduled
    state Draining {
        [*] --> TerminatePods
        TerminatePods --> ReallocateResources
    }
    Draining --> TerminatingVM : Cloud API Scale-Down Call
    TerminatingVM --> [*] : VM Terminated (Cost Stops)
```

### Explanatory Summary
1. **VM Provisioning:** When the Cluster Autoscaler determines a node is needed, it calls the cloud provider's API. The VM transitions through standard hardware/OS setup stages.
2. **Kubelet Bootstrapping:** The VM runs cloud-init scripts, configures system runtimes, installs the Kubelet, and registers with the Kubernetes API Server.
3. **Capacity Decommissioning:** When a node has low utilization, it is marked as `Cordoned` (preventing new pods from scheduling). The Cluster Autoscaler drains it (evicting running pods so they reschedule elsewhere), then signals the Cloud API to terminate the VM.
