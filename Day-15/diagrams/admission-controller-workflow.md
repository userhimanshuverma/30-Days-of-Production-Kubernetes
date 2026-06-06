# Admission Controller Workflow

This diagram outlines how API requests are processed through mutating and validating admission webhooks.

```mermaid
flowchart TD
    Client[Client Request: kubectl/API] --> Authentication[Authentication & Authorization]
    Authentication --> Mutating{1. Mutating Admission?}
    
    Mutating -->|Yes: Inject defaults, sidecars| MutatingWebhooks[Mutating Webhooks]
    Mutating -->|No/Complete| SchemaValidation[2. Schema Validation]
    
    MutatingWebhooks --> SchemaValidation
    SchemaValidation --> Validating{3. Validating Admission?}
    
    Validating -->|Yes: Check policy rules| ValidatingWebhooks[Validating Webhooks]
    Validating -->|No/Passed| EtcdWrite[Write to etcd: Success]
    
    ValidatingWebhooks -->|Pass| EtcdWrite
    ValidatingWebhooks -->|Fail/Reject| Denied[Request Blocked: HTTP 400 Bad Request / 403 Forbidden]
    
    classDef success fill:#27ae60,stroke:#2196f3,stroke-width:2px,color:#fff;
    classDef fail fill:#c0392b,stroke:#a3281c,stroke-width:2px,color:#fff;
    classDef step fill:#2c3e50,stroke:#34495e,stroke-width:2px,color:#fff;
    classDef stage fill:#2980b9,stroke:#2471a3,stroke-width:2px,color:#fff;

    class EtcdWrite success;
    class Denied fail;
    class Client,Authentication,SchemaValidation step;
    class MutatingWebhooks,ValidatingWebhooks stage;
```

### Request Lifecycle Phases:
1. **Mutating Phase:** Modifies incoming resource requests. For example, it might auto-inject a sidecar container, mount volumes, or add default resource limits.
2. **Schema Validation:** Verifies that the JSON/YAML complies with the OpenAPI schema of the resource.
3. **Validating Phase:** Checks the request against strict policy rules (e.g., verifying if image digests are signed, or if a user is trying to deploy a container running as root). Validating controllers are run in parallel.
4. **Persist:** Once all validating webhooks return an allow decision, the request is written to `etcd`.
