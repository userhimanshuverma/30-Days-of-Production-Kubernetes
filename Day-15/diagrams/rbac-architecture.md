# Role-Based Access Control (RBAC) Architecture

This diagram illustrates how Kubernetes associates subjects (Users, Groups, Service Accounts) with permissions using Roles, ClusterRoles, RoleBindings, and ClusterRoleBindings.

```mermaid
graph TD
    %% Define Nodes
    subgraph Subjects ["Subjects (Identities)"]
        User["User (jane.dev@enterprise.com)"]
        Group["Group (system:authenticated)"]
        SA["ServiceAccount (dev-ci-runner)"]
    end

    subgraph NamespaceBound ["Namespace Scope (e.g., namespace: dev)"]
        RB["RoleBinding (developer-rolebinding)"]
        R["Role (developer-role)"]
        Pod["Pods"]
        Svc["Services"]
    end

    subgraph ClusterBound ["Cluster Scope (Non-namespaced)"]
        CRB["ClusterRoleBinding (cluster-auditor-read-only)"]
        CR["ClusterRole (view)"]
        Node["Nodes"]
        PV["PersistentVolumes"]
    end

    %% RBAC Relationships
    User -->|Bound by| RB
    SA -->|Bound by| RB
    RB -->|References| R
    R -->|Grants access to| Pod
    R -->|Grants access to| Svc

    User -->|Bound by| CRB
    SA -->|Bound by| CRB
    CRB -->|References| CR
    CR -->|Grants access to| Node
    CR -->|Grants access to| PV
    CR -.->|Can also grant access to| Pod
    
    classDef subjects fill:#2c3e50,stroke:#34495e,stroke-width:2px,color:#fff;
    classDef ns fill:#2980b9,stroke:#2471a3,stroke-width:2px,color:#fff;
    classDef cluster fill:#d35400,stroke:#ba4a00,stroke-width:2px,color:#fff;
    classDef bindings fill:#27ae60,stroke:#2196f3,stroke-width:2px,color:#fff;

    class User,Group,SA subjects;
    class R,Pod,Svc ns;
    class CR,Node,PV cluster;
    class RB,CRB bindings;
```

### Key Differences:
1. **`Role`**: Namespaced policy that defines what API resources and verbs are allowed in a single namespace.
2. **`ClusterRole`**: Cluster-wide policy that defines permissions for non-namespaced resources (like nodes) or namespaced resources across *all* namespaces.
3. **`RoleBinding`**: Granting the permissions of a `Role` (or a `ClusterRole`) to subjects within a specific namespace.
4. **`ClusterRoleBinding`**: Granting permissions of a `ClusterRole` cluster-wide (across all namespaces and non-namespaced resources).
