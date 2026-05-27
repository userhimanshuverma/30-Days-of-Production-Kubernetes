# 01 - Deployment Architecture

This diagram visualizes the structural flow of a Kubernetes Deployment, highlighting the declarative lifecycle loop from the client configuration down to container runtime execution.

```mermaid
graph TD
    %% Styling
    classDef default fill:#1e1e2e,stroke:#cba6f7,stroke-width:2px,color:#cdd6f4;
    classDef k8s fill:#313244,stroke:#89b4fa,stroke-width:2px,color:#cdd6f4;
    classDef storage fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#cdd6f4;
    classDef client fill:#181825,stroke:#f38ba8,stroke-width:2px,color:#cdd6f4;

    Client[kubectl / API Client]:::client -->|1. Submit Manifest| APIServer[kube-apiserver]:::k8s
    APIServer -->|2. Persist State| Etcd[(etcd)]:::storage
    
    subgraph KCM [Kube-Controller-Manager]
        DepCtrl[Deployment Controller]:::k8s
        RSCtrl[ReplicaSet Controller]:::k8s
    end
    
    APIServer -->|3. Watch Events| DepCtrl
    DepCtrl -->|4. Reconcile & Write| APIServer
    APIServer -->|5. Watch Events| RSCtrl
    RSCtrl -->|6. Reconcile & Create Pods| APIServer
    
    subgraph Nodes [Worker Nodes]
        Kubelet1[Kubelet Node 1]:::k8s
        Kubelet2[Kubelet Node 2]:::k8s
    end
    
    APIServer -->|7. Watch Assigned Pods| Kubelet1
    APIServer -->|7. Watch Assigned Pods| Kubelet2
    
    Kubelet1 -->|8. Run Pod Containers| PodA[Pod A]:::default
    Kubelet1 -->|8. Run Pod Containers| PodB[Pod B]:::default
    Kubelet2 -->|8. Run Pod Containers| PodC[Pod C]:::default
```
