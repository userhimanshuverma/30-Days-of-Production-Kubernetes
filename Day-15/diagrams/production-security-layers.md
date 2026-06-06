# Production Security Layers (The 4Cs)

This diagram visualizes the layered defense-in-depth model of Kubernetes security, starting from the physical infrastructure/cloud up to the application code.

```mermaid
graph TD
    subgraph Cloud ["☁️ Cloud / Infrastructure Layer"]
        Firewalls[VPC Firewalls & IAM]
        PhysicalSec[Hypervisor & Host Isolation]
    end

    subgraph Cluster ["☸️ Kubernetes Cluster Layer"]
        RBAC[RBAC Access Controls]
        APISec[API Server Hardening & Auditing]
        NetPol[Network Policies]
        AdmissionCtrl[Admission Controllers]
    end

    subgraph Container ["📦 Container Layer"]
        ImageSign[Image Signing & Verification]
        SecContext[Pod Security Contexts]
        VulnScan[Vulnerability Scanning]
    end

    subgraph Code ["💻 Code / Application Layer"]
        StaticAnalysis[Static Code Analysis / SAST]
        SecureDeps[Dependency Verification]
        SecretScan[Secret Detection in Code]
    end

    %% Layering dependencies
    Cloud --> Cluster
    Cluster --> Container
    Container --> Code
    
    classDef cloud fill:#2980b9,stroke:#2471a3,stroke-width:2px,color:#fff;
    classDef cluster fill:#27ae60,stroke:#2196f3,stroke-width:2px,color:#fff;
    classDef container fill:#e67e22,stroke:#d35400,stroke-width:2px,color:#fff;
    classDef code fill:#8e44ad,stroke:#7d3c98,stroke-width:2px,color:#fff;

    class Cloud,Firewalls,PhysicalSec cloud;
    class Cluster,RBAC,APISec,NetPol,AdmissionCtrl cluster;
    class Container,ImageSign,SecContext,VulnScan container;
    class Code,StaticAnalysis,SecureDeps,SecretScan code;
```

### The 4Cs Security Model:
1. **Cloud/Infrastructure:** The foundation. Secure the OS host, restrict external network access, and apply Cloud provider IAM policies. If the host is compromised, everything running on it is compromised.
2. **Cluster:** Securing the control plane and workloads. This is where RBAC, Network Policies, etcd encryption, and Admission Controllers reside.
3. **Container:** Hardening the artifact. Use minimal base images (distroless), drop privileges in the container runtime, and scan images for CVEs.
4. **Code:** The source layer. Ensure the application code is free of SQL injection, doesn't leak secrets in source, and uses secure dependencies.
