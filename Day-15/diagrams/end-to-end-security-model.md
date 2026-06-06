# End-to-End Kubernetes Security Model

This comprehensive sequence diagram connects all the day's security concepts (RBAC, Service Accounts, Admission Controllers, Secret Protection, and Pod Security Contexts) into a single unified deployment lifecycle.

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Platform Engineer
    participant API as Kube-API Server
    participant RBAC as RBAC Checker
    participant Admin as Admission Controller (PSA/Kyverno)
    participant DB as etcd (KMS Encrypted)
    participant Kubelet as Kubelet (Worker Node)
    participant Pod as Hardened Pod Process

    %% Phase 1: Deploying the Resource
    Dev->>API: Apply Manifest (Deployment + ServiceAccount)
    
    API->>RBAC: Is user authorized to create Deployments & SAs?
    RBAC-->>API: Authorized (Matches RoleBinding)
    
    API->>Admin: Validate Pod Spec against Pod Security Standards
    Note over Admin: Block root user, check read-only rootfs rules
    Admin-->>API: Approved (Meets 'Restricted' standard)
    
    API->>DB: Write encrypted configuration to etcd
    DB-->>API: Confirmed
    
    %% Phase 2: Scheduling and Node Execution
    Note over API, Kubelet: Scheduler assigns Pod to Node
    Kubelet->>API: Fetch Pod Spec and associated Secrets
    API->>DB: Retrieve ciphertext from etcd
    DB-->>API: Encrypted data
    API->>API: Decrypt using KMS provider key
    API-->>Kubelet: Return decrypted Pod Spec and Secret data
    
    %% Phase 3: Container Runtime Hardening
    Kubelet->>Kubelet: Create memory-backed tmpfs volume for Secret
    Kubelet->>Pod: Mount Secret & launch Container with SecurityContext
    
    Note over Pod: Container runs as non-root (10001)<br/>Root FS is Read-Only<br/>Capabilities are Dropped (ALL)<br/>Can read mounted Secret in RAM
```

### Complete Defense-in-Depth Lifecycle:
1. **At the API Gate:** The request is authenticated and authorized via RBAC.
2. **At Admission Control:** The request is validated against organizational policy (PSA/Kyverno).
3. **At the Storage Layer:** The manifest details and secret content are written to etcd in encrypted format.
4. **On the Node:** Kubelet accesses API server using mutual TLS client certificate, downloading secrets only for pods scheduled to itself.
5. **In Memory:** Secrets are stored in RAM (`tmpfs`), preventing host leakage.
6. **In Execution:** The container process runs under restricted Linux user contexts, isolated by kernel namespaces, seccomp filters, and dropped capabilities.
