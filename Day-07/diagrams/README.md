# 📊 Day 7 Architecture Diagrams

This document contains 12 professional, enterprise-grade architecture diagrams visualizing the concepts of Kubernetes configuration, secret management, and external integration.

---

## 1. ConfigMap Architecture
Shows how a ConfigMap resource maps configuration values to Pods via environment variables and volume mounts.

```mermaid
graph TD
    subgraph K8s_API["Kubernetes Control Plane"]
        CM["ConfigMap: app-config<br/>(data: config.properties, API_URL, LOG_LEVEL)"]
    end

    subgraph Pod_Spec["Pod Manifest Specification"]
        EnvRef["env:<br/>- name: APP_LOG_LEVEL<br/>  valueFrom: configMapKeyRef"]
        VolRef["volumes:<br/>- name: config-volume<br/>  configMap: app-config"]
    end

    subgraph Pod_Runtime["Running Pod (Worker Node)"]
        container["App Container Process"]
        subgraph tmpfs["Container Filesystem"]
            mount["/etc/config/config.properties"]
        end
    end

    CM -->|Injected as Env Var| EnvRef
    CM -->|Mounted as File| VolRef
    EnvRef -->|Process Environment| container
    VolRef -->|Symlinked File Mount| mount
    mount -.->|Read by App| container

    style K8s_API fill:#4A154B,stroke:#fff,stroke-width:2px,color:#fff
    style Pod_Runtime fill:#2E0854,stroke:#fff,stroke-width:2px,color:#fff
    style container fill:#6A0DAD,stroke:#fff,stroke-width:1px,color:#fff
```

---

## 2. Secret Architecture
Visualizes how Opaque Secrets are stored Base64-encoded in `etcd`, but decrypted and mounted into Pods using memory-backed `tmpfs` volumes.

```mermaid
graph TD
    subgraph Control_Plane["Kubernetes Control Plane"]
        Secret["Secret: db-credentials<br/>(base64 encoded)"]
        etcd[("etcd Storage<br/>(Encrypted at rest via KMS)")]
    end

    subgraph Node["Worker Node (Kubelet VM)"]
        subgraph Pod["Pod Namespace"]
            subgraph Container["App Container"]
                Process["App Process (reads raw pwd)"]
            end
            MemoryVolume["/tmp/secrets<br/>(tmpfs - RAM Only)"]
        end
    end

    Secret <-->|Stored & Retrieved| etcd
    Secret -->|Kubelet decodes & mounts| MemoryVolume
    MemoryVolume -->|Mounted as Read-Only File| Process

    style Control_Plane fill:#4A154B,stroke:#fff,stroke-width:2px,color:#fff
    style Node fill:#2E0854,stroke:#fff,stroke-width:2px,color:#fff
    style MemoryVolume fill:#6A0DAD,stroke:#fff,stroke-width:1px,color:#fff
    style etcd fill:#333,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 3. Environment Variable Injection Flow
Details the step-by-step process of how Kubelet reads values from ConfigMaps/Secrets and feeds them into container launch scripts.

```mermaid
sequenceDiagram
    autonumber
    participant KAPI as Kubernetes API Server
    participant Kubelet as Kubelet (Node Agent)
    participant CRI as Container Runtime (CRI-O/containerd)
    participant Container as Container Process

    Kubelet->>KAPI: Watch Pod status (Scheduled to node)
    KAPI-->>Kubelet: Return Pod Spec & associated ConfigMaps/Secrets
    Kubelet->>Kubelet: Resolve valueFrom references (Decrypt Secrets)
    Kubelet->>CRI: CreateContainerRequest (includes Env: KEY=VALUE)
    CRI->>Container: Start container process (execve with Env block)
    Container->>Container: Read env vars from OS RAM (process.env)
```

---

## 4. Volume Mounting Workflow
How the Kubelet Volume Manager updates the node disk, creates directory structures, and links ConfigMap/Secret API resources.

```mermaid
graph TD
    subgraph Control_Plane["Control Plane"]
        API["API Server"]
        CM["ConfigMap API Resource"]
    end

    subgraph Kubelet_Runtime["Kubelet (Worker Node)"]
        VolMgr["Volume Manager"]
        NodeDisk["Local Pod Directory<br/>/var/lib/kubelet/pods/<pod-uid>/volumes/kubernetes.io~configmap/"]
    end

    subgraph Container["Runtime Container"]
        MountDir["/etc/app/config/"]
    end

    API <-->|API Watch| VolMgr
    VolMgr -->|1. Fetch CM data| CM
    VolMgr -->|2. Create path & write files| NodeDisk
    VolMgr -->|3. Bind mount to container namespace| MountDir

    style Control_Plane fill:#4A154B,stroke:#fff,stroke-width:2px,color:#fff
    style Kubelet_Runtime fill:#2E0854,stroke:#fff,stroke-width:2px,color:#fff
    style Container fill:#6A0DAD,stroke:#fff,stroke-width:1px,color:#fff
```

---

## 5. Secret Rotation Process
Visualizes Kubelet's reconciliation loop updating mounted volume files and how applications watch these files to reload configurations dynamically.

```mermaid
sequenceDiagram
    autonumber
    actor Admin as DevSecOps / GitOps
    participant API as Kubernetes API Server
    participant Kubelet as Kubelet Volume Manager
    participant Disk as Node Disk (Symlink targets)
    participant App as Application Process

    Admin->>API: Update Secret data (e.g., API key v2)
    Note over Kubelet: Kubelet Poll Loop (default < 60s)
    Kubelet->>API: Fetch latest Secret representation
    Kubelet->>Disk: Write new secret files to new directory
    Kubelet->>Disk: Update symlink (..data points to new directory atomic change)
    App->>Disk: FileWatcher event triggered (inotify)
    App->>Disk: Read newly updated files from disk
    App->>App: Reload internal connection pool/config
```

---

## 6. Vault Integration Architecture
Illustrates the HashiCorp Vault Agent Injector workflow, mutating the Pod Spec to insert a Sidecar container that authenticates and mounts secrets.

```mermaid
graph LR
    subgraph Control_Plane["Kubernetes Cluster"]
        Mutator["Vault Agent Mutating Webhook"]
        PodSpec["Original Pod Spec"]
        MutatedPodSpec["Mutated Pod Spec<br/>(Init Container + Sidecar)"]
    end

    subgraph Pod_Runtime["Pod Namespace"]
        Init["Vault Init Container"]
        Sidecar["Vault Agent Sidecar"]
        App["App Container"]
        SharedVol["Shared Volume (tmpfs)<br/>/vault/secrets/"]
    end

    subgraph External["External Services"]
        Vault["HashiCorp Vault Server"]
    end

    PodSpec -->|1. Submit Pod| Mutator
    Mutator -->|2. Inject Sidecar/Init Config| MutatedPodSpec
    MutatedPodSpec -->|3. Schedule| Pod_Runtime
    Init -->|4. Authenticate & Fetch Secrets| Vault
    Init -->|5. Write initial secrets| SharedVol
    Sidecar -->|6. Keep token active & rotate secrets| Vault
    Sidecar -->|7. Update secrets| SharedVol
    SharedVol -->|8. Read dynamic secrets| App

    style Control_Plane fill:#4A154B,stroke:#fff,stroke-width:2px,color:#fff
    style Pod_Runtime fill:#2E0854,stroke:#fff,stroke-width:2px,color:#fff
    style External fill:#333,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 7. External Secrets Operator (ESO) Workflow
Details how External Secrets Operator bridges external cloud APIs (AWS/GCP/Azure) with native Kubernetes Secret objects.

```mermaid
graph TD
    subgraph Cloud_Provider["Cloud Secret Manager (e.g., AWS Secrets Manager)"]
        CloudSecret["Secret Value: 'super-secret-password'"]
    end

    subgraph K8s_Cluster["Kubernetes Cluster"]
        subgraph ESO_Namespace["ESO System"]
            ESO_Controller["External Secrets Controller"]
            Store["SecretStore / ClusterSecretStore<br/>(Auth: IAM Roles for ServiceAccounts)"]
        end

        subgraph Dev_Namespace["Application Namespace"]
            ExtSecret["ExternalSecret CRD<br/>(Defines keys to fetch)"]
            K8sSecret["Kubernetes Secret<br/>(Auto-generated & Sync'd)"]
            Pod["Application Pod"]
        end
    end

    ESO_Controller -->|1. Reconcile| ExtSecret
    ESO_Controller -->|2. Read auth configuration| Store
    Store -->|3. Assume Role & Fetch| CloudSecret
    ESO_Controller -->|4. Map values & create/update| K8sSecret
    K8sSecret -->|5. Mount / Inject| Pod

    style Cloud_Provider fill:#232F3E,stroke:#fff,stroke-width:2px,color:#fff
    style K8s_Cluster fill:#4A154B,stroke:#fff,stroke-width:2px,color:#fff
    style Dev_Namespace fill:#2E0854,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 8. Application Startup Flow
Visualizes the application boot order: validating presence of secrets/configs, testing connection strings, and handling graceful crashes if dependencies are missing.

```mermaid
graph TD
    Start([1. Pod Container Starts]) --> CheckEnv{2. Environment Variables<br/>present?}
    CheckEnv -- No --> FailEnv[3. Log Missing Var Name & Exit 1]
    CheckEnv -- Yes --> CheckFiles{4. Mounted Config Files<br/>exist & readable?}
    CheckFiles -- No --> FailFiles[5. Log Access Denied/Missing & Exit 1]
    CheckFiles -- Yes --> ConnectDB{6. Attempt DB Connection<br/>with injected Secret}
    ConnectDB -- Timeout/Auth Error --> Retry{7. Max Retries<br/>Exceeded?}
    Retry -- Yes --> FailConn[8. Log DB Connection Failed & Exit 1]
    Retry -- No --> Wait[9. Backoff & Sleep 2s] --> ConnectDB
    ConnectDB -- Success --> InitApp[10. Initialize App Server]
    InitApp --> StartServer([11. Open Port, Startup Probe Success])

    style Start fill:#4C0099,stroke:#fff,stroke-width:2px,color:#fff
    style StartServer fill:#006633,stroke:#fff,stroke-width:2px,color:#fff
    style FailEnv fill:#990000,stroke:#fff,stroke-width:2px,color:#fff
    style FailFiles fill:#990000,stroke:#fff,stroke-width:2px,color:#fff
    style FailConn fill:#990000,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 9. Multi-Environment Configuration
Shows how base configurations are overlaid using GitOps directories or Kustomize/Helm values to inject environment-specific overrides.

```mermaid
graph TD
    subgraph Git_Repository["Git Repository Structure"]
        Base["base/<br/>- deployment.yaml<br/>- service.yaml<br/>- configmap.yaml (default values)"]
        Dev["overlays/dev/<br/>- kustomization.yaml<br/>- config-override.properties (dev db, debug log)"]
        Prod["overlays/prod/<br/>- kustomization.yaml<br/>- config-override.properties (prod db, error log)"]
    end

    subgraph Clusters["Kubernetes Target Environments"]
        DevCluster["Dev Cluster (Namespace: dev)"]
        ProdCluster["Prod Cluster (Namespace: prod)"]
    end

    Base --> Dev
    Base --> Prod
    Dev -->|Kustomize Build & Apply| DevCluster
    Prod -->|Kustomize Build & Apply| ProdCluster

    style Git_Repository fill:#333,stroke:#fff,stroke-width:2px,color:#fff
    style DevCluster fill:#003366,stroke:#fff,stroke-width:2px,color:#fff
    style ProdCluster fill:#4C0099,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 10. GitOps Configuration Architecture
Displays the security separation where Git only contains reference pointers (ExternalSecrets), preventing actual credentials from leaking into Git commits.

```mermaid
graph TD
    subgraph Developer_Laptop["Developer Workflow"]
        DevCode["Dev commits code &<br/>ExternalSecret YAML"]
    end

    subgraph Git_Host["Git Repository (e.g., GitHub)"]
        Repo["app-deployment-repo<br/>(NO PLAINTEXT SECRETS)"]
    end

    subgraph GitOps_Controller["GitOps Engine (ArgoCD/Flux)"]
        Argo["ArgoCD Application Controller"]
    end

    subgraph Secure_Storage["Secure Vault"]
        Vault["HashiCorp Vault / Cloud KeyVault"]
    end

    subgraph K8s["Production Cluster"]
        ESO["External Secrets Operator"]
        Secret["Kubernetes Secret"]
        Pod["App Pods"]
    end

    Developer_Laptop -->|Push changes| Repo
    Repo <-->|Sync Watch| Argo
    Argo -->|Deploys app manifests & ExternalSecret| K8s
    ESO -->|Reconciles ExternalSecret| Secret
    ESO <-->|Fetches actual payload securely| Vault
    Secret -.->|Injected| Pod

    style Git_Host fill:#24292e,stroke:#fff,stroke-width:2px,color:#fff
    style Secure_Storage fill:#006633,stroke:#fff,stroke-width:2px,color:#fff
    style K8s fill:#4A154B,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 11. Production Secret Management Architecture
Illustrates a locked-down production flow incorporating RBAC, KMS envelope encryption, NodeRestriction, and read-only volume-based file mounts.

```mermaid
graph TD
    subgraph KMS_Provider["Cloud Key Management (KMS)"]
        DEK["Data Encryption Key (DEK)"]
        KEK["Key Encryption Key (KEK)"]
    end

    subgraph Control_Plane["Control Plane"]
        API["kube-apiserver"]
        etcd[("etcd (Encrypted values)")]
    end

    subgraph Kubelet_Node["Kubelet Worker Node"]
        NodeRBAC["NodeRestriction Admission"]
        subgraph Pod["Pod VM Space"]
            SecretsVolume["tmpfs Volume mount<br/>(RAM-backed disk)"]
            AppProcess["App Container (Non-root user)"]
        end
    end

    KEK -->|Envelope encrypts DEK| DEK
    API -->|1. Write Secret| etcd
    etcd -->|2. Call KMS to encrypt| DEK
    API <-->|3. TLS connection| NodeRBAC
    NodeRBAC -->|4. Limit pod access only to scheduled node| SecretsVolume
    SecretsVolume -->|5. Read-only filesystem| AppProcess

    style KMS_Provider fill:#333,stroke:#fff,stroke-width:2px,color:#fff
    style Control_Plane fill:#4A154B,stroke:#fff,stroke-width:2px,color:#fff
    style Kubelet_Node fill:#2E0854,stroke:#fff,stroke-width:2px,color:#fff
```

---

## 12. End-to-End Secret Retrieval Workflow
Detailed timeline representation of a GitOps deployed pod retrieving an external secret.

```mermaid
sequenceDiagram
    autonumber
    participant Developer as DevSecOps Engineer
    participant Git as Git Repo
    participant ArgoCD as ArgoCD Controller
    participant APIServer as Kubernetes API Server
    participant ESO as External Secrets Operator
    participant CloudSM as Cloud Secret Manager
    participant Pod as Pod Startup

    Developer->>Git: Push ExternalSecret & Deployment manifests
    Git->>ArgoCD: Webhook / Poll detection
    ArgoCD->>APIServer: Apply ExternalSecret & Deployment resources
    APIServer->>ESO: Trigger reconciliation event
    ESO->>CloudSM: Call GetSecretValue API (using IAM Role for ServiceAccount)
    CloudSM-->>ESO: Return Encrypted Payload (e.g. DB Password)
    ESO->>APIServer: Create native K8s Secret (base64 encoded)
    APIServer->>APIServer: Encrypt secret payload at-rest via KMS DEK
    APIServer->>Pod: Mount decrypted secret as tmpfs volume
    Pod->>Pod: App starts, reads file, opens connection pool
```
