# 03 - Controller Reconciliation Loop

This diagram models the execution cycle of a Kubernetes Controller (such as the Deployment or ReplicaSet controller). It continuously runs a control loop to align the actual state of the cluster with the desired state specified in the etcd database.

```mermaid
graph TD
    %% Styling
    classDef step fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef decision fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef action fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;

    Start([Start Reconciliation Loop]) --> Observe[Observe actual cluster state <br> via Informers/Cache]:::step
    Observe --> Compare[Compare desired state <br> spec vs actual status]:::step
    Compare --> Match{Does Actual State <br> equal Desired State?}:::decision
    
    Match -->|Yes| Idle[Wait for state changes / events]:::step
    Match -->|No - Under Replicated| ScaleUp[Instruct API server to create Pods]:::action
    Match -->|No - Over Replicated| ScaleDown[Instruct API server to terminate Pods]:::action
    Match -->|No - Spec Mismatch / Outdated| Rollout[Trigger Rolling Update sequence]:::action
    
    ScaleUp --> Observe
    ScaleDown --> Observe
    Rollout --> Observe
    Idle -->|Event Triggered| Observe
```
