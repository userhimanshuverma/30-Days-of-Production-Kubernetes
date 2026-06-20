# Role-Based Access Control (RBAC) Hardening & Auditing Guide

This guide details best practices for scoping, managing, and auditing Kubernetes RBAC permissions to enforce the Principle of Least Privilege.

---

## 🚫 1. Never Use Wildcards in Production
Using wildcards (`*`) inside RBAC rules gives administrators and pods unrestricted powers. Specify resources and verbs explicitly.

### Bad: Broad Wildcard Permissions
```yaml
# AVOID THIS PATTERN IN PRODUCTION
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
```

### Good: Specific Scoped Access
```yaml
# RECOMMENDED SCENE SCOPE
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
```

---

## ⚙️ 2. Restrict ClusterRoleBindings to Human SREs Only
ServiceAccounts run code processes; they should almost never be bound to the global `cluster-admin` ClusterRole. Lock down the `system:serviceaccounts` group.

To detect who has cluster-admin bindings, SREs should run:
```bash
kubectl get clusterrolebindings -o json | jq '.items[] | select(.roleRef.name=="cluster-admin") | {binding: .metadata.name, subjects: .subjects}'
```

---

## 🔍 3. SRE RBAC Audit Commands Checklist

*   **List all ServiceAccounts with ClusterRole bindings**:
    ```bash
    kubectl get clusterrolebindings -o custom-columns=NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*]
    ```
*   **Query if a specific ServiceAccount can delete resources**:
    ```bash
    kubectl auth can-i delete deployments --as=system:serviceaccount:ai-services:fastapi-ai-sa
    ```
*   **List all ClusterRoles that grant Secrets access**:
    ```bash
    kubectl get clusterroles -o json | jq '.items[] | select(.rules[]?.resources[]? | contains("secrets")) | .metadata.name'
    ```
