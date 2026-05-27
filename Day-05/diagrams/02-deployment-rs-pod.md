# 02 - Deployment -> ReplicaSet -> Pod Relationship

This diagram illustrates the hierarchical relationship between a Deployment resource, the ReplicaSets it creates for version control, and the actual Pods executing the workload.

```mermaid
graph TD
    %% Styling
    classDef depl fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef rs fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef pod fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;
    classDef oldrs fill:#313244,stroke:#6c7086,stroke-width:1px,stroke-dasharray: 5 5,color:#a6adc8;
    classDef oldpod fill:#1e1e2e,stroke:#6c7086,stroke-width:1px,stroke-dasharray: 5 5,color:#a6adc8;

    subgraph Logical Abstraction
        Dep[Deployment: payment-processor]:::depl
    end

    subgraph ReplicaSets [ReplicaSet Version Control]
        RS_New[ReplicaSet: payment-processor-67f9db (v1.1.0)]:::rs
        RS_Old[ReplicaSet: payment-processor-54d8b8 (v1.0.0)]:::oldrs
    end

    subgraph LivePods [Live Pod Instances]
        Pod1[Pod: payment-processor-67f9db-aaa]:::pod
        Pod2[Pod: payment-processor-67f9db-bbb]:::pod
        Pod3[Pod: payment-processor-67f9db-ccc]:::pod
        
        OldPod1[Pod: payment-processor-54d8b8-xxx (Terminated)]:::oldpod
        OldPod2[Pod: payment-processor-54d8b8-yyy (Terminated)]:::oldpod
    end

    Dep -->|Manages (Active - Scale: 3)| RS_New
    Dep -.->|Keeps History (Inactive - Scale: 0)| RS_Old

    RS_New -->|Owns & Reconciles| Pod1
    RS_New -->|Owns & Reconciles| Pod2
    RS_New -->|Owns & Reconciles| Pod3

    RS_Old -.->|Controlled Lifecycle| OldPod1
    RS_Old -.->|Controlled Lifecycle| OldPod2
```
