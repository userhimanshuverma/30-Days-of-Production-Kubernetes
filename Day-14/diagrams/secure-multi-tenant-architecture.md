# Secure Multi-Tenant Network Architecture

This diagram demonstrates a production-hardened multi-tenant security architecture applying default-deny policies, microservices zoning, and egress domain restrictions.

```mermaid
graph TD
    subgraph TenantA [Tenant A Namespace]
        FrontendA[Frontend A Pod]
        BackendA[Backend A Pod]
        DBA[(Postgres A Pod)]
        
        FrontendA ==> |Allowed: Port 8080| BackendA
        BackendA ==> |Allowed: Port 5432| DBA
    end

    subgraph TenantB [Tenant B Namespace]
        FrontendB[Frontend B Pod]
        BackendB[Backend B Pod]
        DBB[(Postgres B Pod)]
        
        FrontendB ==> |Allowed: Port 8080| BackendB
        BackendB ==> |Allowed: Port 5432| DBB
    end

    subgraph ClusterInfra [Kube-System Namespace]
        CoreDNS[CoreDNS Pod]
    end

    %% Network Policy Blocks
    FrontendA -.x |BLOCKED: Ingress Deny| FrontendB
    BackendA -.x |BLOCKED: Cross-Tenant Egress| BackendB
    FrontendB -.x |BLOCKED: Direct Access Deny| DBA
    
    %% Infrastructure Access
    FrontendA ==> |Port 53 UDP| CoreDNS
    FrontendB ==> |Port 53 UDP| CoreDNS
```

### Production Security Boundaries:
1. **Default-Deny-All:** All namespaces apply a global default-deny policy for ingress and egress. This ensures that a newly scheduled Pod is completely isolated until a specific policy is written for it.
2. **Namespace Segregation:** Ingress rules are configured with `namespaceSelector` labels to guarantee that workloads in `Tenant A` are mathematically prevented from opening sockets to endpoints in `Tenant B`.
3. **Database Security Zones:** Database Pods are isolated from direct frontend network contact. They only whitelist ingress from the corresponding backend tier Pods.
4. **Core Infrastructure Whitelisting:** Both tenant namespaces are configured with explicit egress policies to permit UDP/TCP traffic on port `53` to the `kube-system` namespace, enabling CoreDNS resolution.
