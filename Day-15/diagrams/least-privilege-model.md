# Least Privilege Access Model

This comparative diagram highlights the differences between secure (least privilege) and insecure (overprivileged) configurations.

```mermaid
graph TD
    subgraph BadPattern ["❌ Bad Practice: Overprivileged Access"]
        UserBad["ServiceAccount / User"] -->|Bound to wildcard| RoleBad["Role: admin-like"]
        RoleBad -->|apiGroups: '*'| GrantAllGroup["All API Groups"]
        RoleBad -->|resources: '*'| GrantAllRes["All Resources"]
        RoleBad -->|verbs: '*'| GrantAllVerb["All Verbs (create, delete, update)"]
        
        NoteOverBad["If this workload is compromised, the attacker inherits full control of the cluster."]
    end

    subgraph GoodPattern ["✅ Good Practice: Least Privilege"]
        UserGood["ServiceAccount: app-reader"] -->|Bound to scoped| RoleGood["Role: pod-reader"]
        RoleGood -->|apiGroups: ''| GrantCore["Core API Group only"]
        RoleGood -->|resources: ['pods']| GrantPods["Pods only (No Secrets, ConfigMaps, etc.)"]
        RoleGood -->|verbs: ['get', 'list']| GrantRead["Read-only (No write, delete, or create)"]
        
        NoteOverGood["Workload compromise is blast-isolated to reading pod metadata in a single namespace."]
    end

    classDef secure fill:#27ae60,stroke:#2196f3,stroke-width:2px,color:#fff;
    classDef insecure fill:#c0392b,stroke:#a3281c,stroke-width:2px,color:#fff;
    classDef rule fill:#2c3e50,stroke:#34495e,stroke-width:2px,color:#fff;

    class UserGood,RoleGood,GrantCore,GrantPods,GrantRead secure;
    class UserBad,RoleBad,GrantAllGroup,GrantAllRes,GrantAllVerb insecure;
    class NoteOverBad,NoteOverGood rule;
```

### Best Practices for Least Privilege:
* **Avoid wildcards (`*`):** Explicitly name resources and API groups.
* **Namespace Scoping:** Use `Role` and `RoleBinding` instead of `ClusterRole` and `ClusterRoleBinding` unless cluster-wide scope is strictly required.
* **Separation of Concerns:** Create unique Service Accounts for each microservice rather than letting them share the `default` service account.
* **Write vs. Read:** Minimize the allocation of `create`, `update`, `patch`, and `delete` verbs.
