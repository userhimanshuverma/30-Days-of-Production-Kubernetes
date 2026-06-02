# 📊 Day 11: Helm Deep Dive Diagrams

This collection contains 12 professional visual blueprints illustrating Helm's architecture, templating loops, lifecycle states, upgrade mechanics, and enterprise GitOps integration.

---

## 1. Helm v3 Architecture
Helm v3 operates as a client-only CLI. It communicates directly with the Kubernetes API Server and stores release histories in cluster-native `Secrets` within the deployment namespace.

```mermaid
graph TD
    subgraph "Workstation / CI/CD Runner"
        CLI["Helm CLI\n(Binary: helm)"]
        LocalKubeconfig["kubeconfig\n(Auth context)"]
        ChartFiles["Helm Chart\n(Templates, values.yaml)"]
    end

    subgraph "Kubernetes Control Plane"
        APIServer["Kubernetes API Server\n(kube-apiserver)"]
        ETCD["etcd Database\n(Cluster State Store)"]
    end

    subgraph "Target Namespace (e.g., prod)"
        ReleaseSecret1["Secret: sh.helm.release.v1.app.v1\n(Compressed Config)"]
        ReleaseSecret2["Secret: sh.helm.release.v1.app.v2\n(Current Release)"]
        K8sResources["App Resources\n(Pods, Services, Ingress)"]
    end

    CLI -->|1. Reads Auth & Context| LocalKubeconfig
    CLI -->|2. Compiles Templates| ChartFiles
    CLI -->|3. HTTP REST Requests| APIServer
    APIServer <-->|Reads/Writes| ETCD
    APIServer -->|4. Deploys/Updates| K8sResources
    APIServer -->|5. Manages Release State| ReleaseSecret2

    style CLI fill:#9c27b0,stroke:#7b1fa2,stroke-width:2px,color:#fff
    style APIServer fill:#00bcd4,stroke:#0097a7,stroke-width:2px,color:#fff
    style ReleaseSecret2 fill:#4caf50,stroke:#388e3c,stroke-width:2px,color:#fff
```

---

## 2. Helm Chart Folder Structure
The file layout of a standard Helm chart package.

```mermaid
graph TD
    ChartDir["my-app-chart/ (Root)"]
    ChartYaml["Chart.yaml\n(Metadata, Chart & App Versions)"]
    ValuesYaml["values.yaml\n(Default Variables)"]
    ChartsDir["charts/\n(Subcharts / Dependencies)"]
    TemplatesDir["templates/\n(Blueprints)"]
    
    Helpers["_helpers.tpl\n(Reusable named templates)"]
    Notes["NOTES.txt\n(Post-deployment notes)"]
    DeployYAML["deployment.yaml\n(Pod blueprint)"]
    SvcYAML["service.yaml\n(Access blueprint)"]
    IngressYAML["ingress.yaml\n(Traffic routing)"]

    ChartDir --> ChartYaml
    ChartDir --> ValuesYaml
    ChartDir --> ChartsDir
    ChartDir --> TemplatesDir

    TemplatesDir --> Helpers
    TemplatesDir --> Notes
    TemplatesDir --> DeployYAML
    TemplatesDir --> SvcYAML
    TemplatesDir --> IngressYAML

    style ChartDir fill:#1565c0,stroke:#0d47a1,color:#fff
    style TemplatesDir fill:#e65100,stroke:#b71c1c,color:#fff
```

---

## 3. Template Rendering Workflow
How Helm compiles parameters and blueprints into raw manifest code ready for Kubernetes ingestion.

```mermaid
graph LR
    subgraph "Inputs"
        Templates["templates/*.yaml\n(YAML Blueprints)"]
        DefaultValues["values.yaml\n(Base values)"]
        EnvValues["values-prod.yaml\n(Env-specific overrides)"]
        CliValues["--set replicas=5\n(CLI Overrides)"]
    end

    subgraph "Helm Rendering Engine"
        GoEngine["Go template engine\n(text/template)"]
        Sprig["Sprig Library\n(String, Math, Crypto helpers)"]
    end

    OutputYAML["Rendered Manifests\n(Pure Kubernetes YAML)"]

    Templates --> GoEngine
    DefaultValues --> GoEngine
    EnvValues --> GoEngine
    CliValues --> GoEngine
    Sprig -.-> GoEngine
    GoEngine -->|Validates & Compiles| OutputYAML

    style GoEngine fill:#ef6c00,stroke:#d84315,color:#fff
    style OutputYAML fill:#2e7d32,stroke:#1b5e20,color:#fff
```

---

## 4. Values Injection & Merge Precedence
The hierarchy of configuration merging. Values listed lower in the diagram override those above them.

```mermaid
graph TD
    DefaultValues["1. Base values.yaml (In-Chart Defaults)\n(Lowest Precedence)"]
    EnvValues["2. Environment-specific values-env.yaml\n(Overrides Base Defaults)"]
    CliValues["3. CLI Overrides (--set key=value)\n(Highest Precedence)"]
    
    Merged["Merged Configmap Matrix\n(Final Context passed to Templates)"]

    DefaultValues -->|Merged Into| Merged
    EnvValues -->|Overrides & Merged Into| Merged
    CliValues -->|Forces Overwrites| Merged

    style CliValues fill:#c62828,stroke:#b71c1c,color:#fff
    style Merged fill:#2e7d32,stroke:#1b5e20,color:#fff
```

---

## 5. Release Lifecycle States
The state machine of a Helm release revision.

```mermaid
stateDiagram-v2
    [*] --> PENDING_INSTALL : helm install
    PENDING_INSTALL --> DEPLOYED : Hooks Pass & Resources Created
    PENDING_INSTALL --> FAILED : Timeout / Hook Mismatch
    
    DEPLOYED --> PENDING_UPGRADE : helm upgrade
    PENDING_UPGRADE --> DEPLOYED : Upgrade Successful
    PENDING_UPGRADE --> FAILED : Validation / Rollback Required
    
    FAILED --> DEPLOYED : helm rollback
    DEPLOYED --> SUPERSEDED : Upgraded to New Revision
    DEPLOYED --> UNINSTALLED : helm uninstall
    FAILED --> UNINSTALLED : helm uninstall
    UNINSTALLED --> [*]

    style DEPLOYED fill:#c8e6c9,stroke:#4caf50
    style FAILED fill:#ffcdd2,stroke:#f44336
```

---

## 6. Upgrade Workflow (Three-Way Merge Patch)
Helm v3 uses a three-way strategic merge patch comparing: the **old release manifest**, the **live cluster state** (which may have manual changes), and the **proposed new manifest**.

```mermaid
graph TD
    OldRelease["1. Old Release Manifest\n(Saved in Helm Secret v1)"]
    LiveState["2. Live Cluster State\n(May include manual modifications)"]
    NewManifest["3. Proposed New Manifest\n(Rendered from templates)"]
    
    MergeEngine["3-Way Strategic Merge Engine"]
    DiffPatch["Generated Patch Payload\n(Only changes applied)"]
    K8sCluster["Active Kubernetes Cluster"]

    OldRelease --> MergeEngine
    LiveState --> MergeEngine
    NewManifest --> MergeEngine
    
    MergeEngine --> DiffPatch
    DiffPatch -->|Updates Resources| K8sCluster

    style MergeEngine fill:#3f51b5,stroke:#303f9f,color:#fff
    style K8sCluster fill:#00bcd4,stroke:#0097a7,color:#fff
```

---

## 7. Rollback Workflow
When a rollback is triggered, Helm extracts historical manifests from its Release Secret store, processes them, and commits them as a new revision.

```mermaid
graph LR
    User["SRE Operator"] -->|helm rollback app 1| K8sAPI["Kubernetes API Server"]
    
    subgraph "Secret Store (Release History)"
        SecretV3["sh.helm.release.v1.app.v3\n(Failed Revision)"]
        SecretV2["sh.helm.release.v1.app.v2\n(Good Config Template)"]
        SecretV1["sh.helm.release.v1.app.v1\n(First Release)"]
    end
    
    K8sAPI -->|1. Fetches Manifest of Rev 2| SecretV2
    K8sAPI -->|2. Submits Rev 2 Configuration| Deployments["Live Pods / Resources"]
    K8sAPI -->|3. Generates New Release Record| SecretV4["sh.helm.release.v1.app.v4\n(Active - Restored State)"]

    style SecretV2 fill:#c8e6c9,stroke:#4caf50
    style SecretV4 fill:#e1bee7,stroke:#8e24aa
```

---

## 8. Multi-Environment Promotion Pipeline
How a single Helm chart is promoted across environments using value overlays.

```mermaid
graph TD
    BuildChart["Build Helm Chart\n(Version: 1.2.0-rc1)"]
    
    subgraph "Dev Environment"
        DevDeploy["helm upgrade --install\n-f values-dev.yaml"] --> DevCluster["Dev Cluster (Namespace: dev)"]
    end
    
    subgraph "Staging Environment"
        StgDeploy["helm upgrade --install\n-f values-stg.yaml"] --> StgCluster["Staging Cluster (Namespace: staging)"]
    end
    
    subgraph "Production Environment"
        ProdDeploy["helm upgrade --install\n-f values-prod.yaml"] --> ProdCluster["Prod Cluster (Namespace: prod)"]
    end

    BuildChart -->|Promote| DevDeploy
    DevCluster -->|Verification Pass| StgDeploy
    StgCluster -->|Integration Pass| ProdDeploy

    style BuildChart fill:#ffeb3b,stroke:#fbc02d
    style DevCluster fill:#b3e5fc,stroke:#03a9f4
    style StgCluster fill:#ffe0b2,stroke:#ff9800
    style ProdCluster fill:#c8e6c9,stroke:#4caf50
```

---

## 9. Helm Repository Architecture
Comparison between traditional HTTP/S static Chart repositories and modern OCI registries.

```mermaid
graph TD
    ChartSrc["Local Chart Source"] -->|helm package| PackagedChart["my-app-1.2.0.tgz"]
    
    subgraph "A. HTTP/S Repository Pattern"
        PackagedChart -->|Upload tgz| ObjectStore["Object Storage (S3 / GCS)"]
        UpdateIndex["helm repo index"] -->|Generates/Uploads| IndexYaml["index.yaml\n(Metadata & URL Pointer)"]
        IndexYaml -.-> ObjectStore
    end
    
    subgraph "B. OCI Registry Pattern (Modern Standard)"
        PackagedChart -->|helm push| OCIRegistry["OCI Registry\n(ECR / GHCR / Harbor)"]
    end

    style ObjectStore fill:#ffe0b2,stroke:#ff9800
    style OCIRegistry fill:#c8e6c9,stroke:#4caf50
```

---

## 10. Production CI/CD Pipeline
Continuous integration and continuous deployment pipeline using Helm.

```mermaid
graph LR
    CodeCommit["1. Git Commit / Push"] --> CI["2. CI Runner\n(GitHub Actions / GitLab CI)"]
    
    subgraph "Lint & Test Stage"
        CI -->|Run| Lint["helm lint"]
        CI -->|Run| TemplateCheck["helm template --debug"]
        CI -->|Run| UnitTest["helm-unittest plugin"]
    end

    Lint & TemplateCheck & UnitTest -->|Success| Publish["3. Package & Push to OCI"]
    Publish --> CD["4. CD Trigger"]
    CD -->|Dry Run Check| DryRun["helm upgrade --dry-run --install"]
    DryRun -->|Apply Deploy| K8sCluster["5. Kubernetes Cluster"]

    style CI fill:#ede7f6,stroke:#5e35b1
    style K8sCluster fill:#c8e6c9,stroke:#4caf50
```

---

## 11. GitOps Integration (ArgoCD & Flux)
The GitOps approach: the Git repository is the source of truth, and controllers in the cluster pull charts and values to reconcile state.

```mermaid
graph TD
    Developer["Developer"] -->|Pushes Code / Values| GitRepo["Git Repository\n(Declarative Desired State)"]
    
    subgraph "Kubernetes Cluster"
        ArgoCD["ArgoCD / Helm Controller\n(Watches Git Repository)"]
        HelmCtrl["Helm Controller / Engine\n(Reconciles Cluster State)"]
        ActiveResources["Live Resources\n(Running App Pods)"]
    end

    GitRepo <-->|1. Polling / Webhook Sync| ArgoCD
    ArgoCD -->|2. Evaluates State Drift| HelmCtrl
    HelmCtrl -->|3. Applies Merge Patch| ActiveResources
    ActiveResources -.->|4. Status Reports| ArgoCD

    style GitRepo fill:#fbe9e7,stroke:#ff5722
    style ArgoCD fill:#e1bee7,stroke:#8e24aa,color:#fff
    style ActiveResources fill:#c8e6c9,stroke:#4caf50
```

---

## 12. Enterprise Production Deployment Architecture
An enterprise-grade release topology. A single Helm upgrade coordinates the entire system, configuring autoscaling, high-availability pod layout, security parameters, and routing structures.

```mermaid
graph TD
    IngressRoute["Ingress (Ingress Resource)"] -->|Routes HTTP Host| ServiceCluster["ClusterIP Service"]
    
    subgraph "Availability Zone A"
        ServiceCluster -->|Load Balances| PodA["App Pod Replica 1"]
    end
    
    subgraph "Availability Zone B"
        ServiceCluster -->|Load Balances| PodB["App Pod Replica 2"]
    end

    PodA <-->|Runs under| PodAffinity["Pod Anti-Affinity Rule\n(Anti-colocation in AZs)"]
    PodB <-->|Runs under| PodAffinity

    PDB["PodDisruptionBudget\n(minAvailable: 1)"] -.-> PodA
    PDB -.-> PodB

    HPA["Horizontal Pod Autoscaler\n(CPU target: 70%)"] -.-> Autoscaling["Deployment Controller\n(Scales Pods)"]
    Autoscaling --> PodA
    Autoscaling --> PodB

    style ServiceCluster fill:#bbdefb,stroke:#1e88e5
    style PodA fill:#e8f5e9,stroke:#388e3c
    style PodB fill:#e8f5e9,stroke:#388e3c
```
