# Secure Cluster Architecture

This architecture diagram outlines the security boundaries and network isolation points in a production-grade Kubernetes cluster.

```mermaid
graph TD
    %% Internet Boundary
    Internet((Public Internet)) -->|HTTPS/TLS| LB[External Load Balancer]
    
    %% DMZ / Ingress Network
    subgraph DMZ ["Demilitarized Zone / Ingress"]
        LB -->|Routes to| IngressController[Ingress Controller (e.g. NGINX)]
    end
    
    %% Secure Private VPC Boundary
    subgraph VPC ["Private VPC Network"]
        
        %% Control Plane Subnet
        subgraph ControlPlane ["Control Plane (Private Subnet)"]
            APIServer[Kube-API Server]
            etcd[(etcd: Encrypted at Rest)]
            KMS[KMS Plugin / Vault]
            
            APIServer <-->|Saves state| etcd
            APIServer <-->|Keys| KMS
        end

        %% Worker Nodes Subnet
        subgraph NodeSubnet ["Worker Nodes (Private Subnet)"]
            Node1[Worker Node 1]
            Node2[Worker Node 2]
            
            subgraph PodsNetwork1 ["Node 1 Pod Network"]
                PodA[Secure Pod A]
                PodB[Secure Pod B]
            end
            
            subgraph PodsNetwork2 ["Node 2 Pod Network"]
                PodC[Secure Pod C]
            end
        end
    end
    
    %% Control Flow
    IngressController -->|Secured by NetworkPolicies| PodA
    Kubelet1[Kubelet] -->|TLS Client Cert Auth| APIServer
    Kubelet2[Kubelet] -->|TLS Client Cert Auth| APIServer
    
    Node1 --- Kubelet1
    Node2 --- Kubelet2
    
    %% Style Classes
    classDef boundary fill:#c0392b,stroke:#7f8c8d,stroke-width:2px,color:#fff;
    classDef internal fill:#2c3e50,stroke:#34495e,stroke-width:2px,color:#fff;
    classDef control fill:#2980b9,stroke:#2471a3,stroke-width:2px,color:#fff;
    classDef worker fill:#27ae60,stroke:#2196f3,stroke-width:2px,color:#fff;

    class Internet,LB boundary;
    class APIServer,etcd,KMS control;
    class Node1,Node2,PodA,PodB,PodC worker;
    class DMZ,VPC,ControlPlane,NodeSubnet internal;
```

### Key Security Features:
* **Private API Endpoint:** Kube-API Server is hosted inside a private subnet and is not accessible from the public internet. Access is restricted to trusted VPNs, bastion hosts, or cloud interconnects.
* **Network Policies:** Worker node subnets use egress/ingress rules to ensure pods can only talk to approved resources.
* **etcd Isolation:** The key-value store only accepts connections from the API Server via mutual TLS (mTLS). It is encrypted using KMS plugins.
* **Ingress Termination:** External traffic is terminated at the Ingress Controller, which applies security headers, SSL termination, and WAF rules before forwarding requests.
