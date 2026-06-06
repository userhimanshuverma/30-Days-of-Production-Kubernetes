# Authorization Workflow

This diagram outlines how Kubernetes processes a request through different authorization modules (Node, RBAC, Webhook) and determines whether to allow or deny the action.

```mermaid
flowchart TD
    Request([Authenticated Request]) --> AuthZCheck{Authorization Configured?}
    
    AuthZCheck -->|Yes| NodeModule{1. Node Authorizer?}
    
    NodeModule -->|Match: Kubelet requesting own Node/Pod| Allow([Allow Request])
    NodeModule -->|No Match| RBACModule{2. RBAC Authorizer?}
    
    RBACModule -->|Role/ClusterRole permissions match| Allow
    RBACModule -->|No Match| WebhookModule{3. Webhook Authorizer?}
    
    WebhookModule -->|External policy decision: Allow| Allow
    WebhookModule -->|External policy decision: Deny/Ignore| DefaultDeny{All modules checked?}
    
    DefaultDeny -->|Yes| Deny([Deny Request: HTTP 403 Forbidden])
    
    classDef success fill:#27ae60,stroke:#2196f3,stroke-width:2px,color:#fff;
    classDef fail fill:#c0392b,stroke:#a3281c,stroke-width:2px,color:#fff;
    classDef process fill:#2c3e50,stroke:#34495e,stroke-width:2px,color:#fff;
    classDef decision fill:#f39c12,stroke:#d35400,stroke-width:2px,color:#fff;

    class Allow success;
    class Deny fail;
    class Request process;
    class NodeModule,RBACModule,WebhookModule,DefaultDeny,AuthZCheck decision;
```

### Authorization Modules:
1. **Node Authorizer:** A special-purpose authorization mode that specifically authorizes API requests made by kubelets to read/modify their own node or pods.
2. **RBAC (Role-Based Access Control):** The default authorization mode. Evaluates Roles and ClusterRoles configured within the cluster.
3. **Webhook Authorizer:** Delegates authorization decisions to an external HTTP endpoint (e.g., OPA Gatekeeper or custom policy engines).
4. **Deny by Default:** If no authorizer explicitly allows the request, it is denied by default (least privilege principle).
