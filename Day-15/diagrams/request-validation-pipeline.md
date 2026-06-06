# Request Validation Pipeline

This workflow diagram describes the sequence of stages a request undergoes inside the `kube-apiserver` before write confirmation.

```mermaid
sequenceDiagram
    autonumber
    actor Client as kubectl / Client
    participant API as Kube-API Server
    participant AuthN as Authentication Handler
    participant AuthZ as Authorization Handler
    participant Mutating as Mutating Admission Webhook
    participant Schema as Schema Validator
    participant Validating as Validating Admission Webhook
    participant DB as etcd Database

    Client->>API: HTTP Request (POST /api/v1/namespaces/dev/pods)
    
    API->>AuthN: Authenticate Request? (Certs/JWT/Token)
    Note over AuthN: Validates identity
    AuthN-->>API: Identity Resolved (Subject, Groups)

    API->>AuthZ: Authorize Action? (RBAC / Webhook)
    Note over AuthZ: Checks verbs & resources
    AuthZ-->>API: Allowed (jane has 'create' on 'pods')

    API->>Mutating: Run Mutating Webhooks
    Note over Mutating: Injects sidecars / defaults (e.g. Istio)
    Mutating-->>API: Modified Manifest JSON

    API->>Schema: Validate OpenAPI Schema
    Note over Schema: Verifies syntax & types
    Schema-->>API: Schema Valid

    API->>Validating: Run Validating Webhooks
    Note over Validating: Checks policy compliance (e.g. Kyverno/OPA)
    Validating-->>API: Allowed / Approved

    API->>DB: Write to etcd
    DB-->>API: Persist Confirmed
    API-->>Client: HTTP 201 Created (Success Response)
```

### Critical Stages:
* **Fail-Closed vs. Fail-Open Webhooks:** During Mutating and Validating phases, if a webhook does not respond, the API Server will either block the request (fail-closed) or allow it (fail-open) depending on the configuration. In production, security webhooks should be configured to fail-closed.
* **OpenAPI Schema Validation:** Prevents malformed or corrupted objects from polluting the etcd state.
