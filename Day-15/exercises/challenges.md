# 🏆 Day 15: Exercises and Challenges

These challenges are designed to reinforce your hands-on understanding of RBAC, workload hardening, and Namespace policies in production environments.

---

## Challenge 1: The Principle of Least Privilege (RBAC)

### Scenario
An external analytics service needs to inspect active workloads inside the `production` namespace. You must grant it read access to **Pods and Services only**. It must **not** be allowed to read Secrets, ConfigMaps, or modify any resources.

### Task Checklist
- [ ] Create a namespace called `production`.
- [ ] Create a ServiceAccount named `analytics-collector` in `production`.
- [ ] Create a Role named `read-only-pods-services` in `production` that grants `get`, `list`, and `watch` permissions only for `pods` and `services`.
- [ ] Create a RoleBinding named `analytics-collector-binding` binding the service account to the role.
- [ ] Use `kubectl auth can-i` to verify:
  1. Can the service account list pods in `production`? (Must be `yes`)
  2. Can the service account delete pods in `production`? (Must be `no`)
  3. Can the service account read secrets in `production`? (Must be `no`)

---

## Challenge 2: Pod Security Context Hardening

### Scenario
A developer has submitted a deployment configuration for a backend application that runs as root and writes files to the local root filesystem. You need to harden this deployment to run in a namespace with strict security rules.

Here is the unhardened manifest (`unhardened-app.yaml`):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unhardened-backend
  namespace: restricted-namespace
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: web
          image: nginx
          ports:
            - containerPort: 80
```

### Task Checklist
- [ ] Create the namespace `restricted-namespace` and label it to enforce the `restricted` Pod Security Standard.
- [ ] Attempt to apply `unhardened-app.yaml` to this namespace. Observe the admission error.
- [ ] Rewrite the manifest to fix the issues:
  1. Add a container-level `securityContext` dropping all capabilities, disabling privilege escalation, and mounting the root filesystem as read-only.
  2. Add a pod-level `securityContext` running as user `10001` and group `10001`.
  3. Configure a memory-based (`tmpfs`) volume mount for `/var/cache/nginx`, `/var/run`, and `/tmp` so Nginx can write temp cache files while the root filesystem remains read-only.
  4. Note: Use `nginxinc/nginx-unprivileged` as the image since official Nginx defaults to port 80 (which requires privileged root access) and runs as root.
- [ ] Deploy the hardened application and verify that the pods scale to `Running` status.

---

## Challenge 3: Audit Permission Leakage

### Scenario
You are performing a security audit of a staging cluster. You suspect there is a ClusterRoleBinding that grants wildcard write permissions to a service account, which violates the security policy.

### Task Checklist
- [ ] Write a script or kubectl query to find all `ClusterRoleBindings` referencing the `system:masters` group, or any ClusterRoleBinding that references a ClusterRole containing wildcard `*` permissions.
- [ ] Generate a markdown security audit report listing:
  - The names of the overprivileged bindings.
  - The subjects (Users/Groups/Service Accounts) bound to them.
  - Recommended actions to replace them with namespace-scoped RoleBindings.
