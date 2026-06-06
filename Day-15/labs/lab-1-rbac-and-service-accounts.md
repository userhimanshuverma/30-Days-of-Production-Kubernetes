# 🧪 Lab 1: Configure RBAC & Service Accounts

This hands-on lab guides you through configuring namespace-scoped RBAC roles, binding them to users and service accounts, and validating their enforcement.

---

## Prerequisites
- A running Kubernetes cluster (Kind, Minikube, or a development cluster).
- `kubectl` CLI installed and configured.

---

## Step 1: Create the target Namespace and Service Account

First, let's create a dedicated namespace `dev` to isolate our configurations, and establish a new workload identity (Service Account).

```bash
# Create the development namespace
kubectl create namespace dev

# Create the ServiceAccount for our CI/CD pipelines
kubectl create serviceaccount dev-ci-runner -n dev
```

Inspect the created Service Account:
```bash
kubectl get serviceaccount dev-ci-runner -n dev -o yaml
```

---

## Step 2: Apply the developer Role and RoleBinding

We will use the pre-built manifests to establish permissions. 

1. Review [manifests/developer-role.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/developer-role.yaml). This Role permits read-write operations on Deployments, Services, and Pods within the `dev` namespace, but restricts Secrets to `get` operations on single instances (no listing allowed).
2. Apply the Role:
   ```bash
   kubectl apply -f manifests/developer-role.yaml
   ```

3. Review [manifests/developer-binding.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/developer-binding.yaml). This RoleBinding maps our Role to:
   - The ServiceAccount `dev-ci-runner`.
   - A human user `jane.dev@enterprise.com`.
4. Apply the Binding:
   ```bash
   kubectl apply -f manifests/developer-binding.yaml
   ```

Verify the resources are created:
```bash
kubectl get roles,rolebindings -n dev
```

---

## Step 3: Test permissions using `kubectl auth can-i`

Kubernetes provides an authorization evaluation tool inside the client CLI. We can simulate API actions as if we were our newly created identities.

### Test 1: Validate Deployments Management
As the `dev-ci-runner` Service Account, check if we can manage Deployments in the `dev` namespace:
```bash
kubectl auth can-i create deployments -n dev \
  --as=system:serviceaccount:dev:dev-ci-runner
```
*Expected Output: `yes`*

### Test 2: Validate Secret Listing Restrictions
To prevent secret leaks, listing all secrets in the namespace was omitted from the role rule. Test if the Service Account can list secrets:
```bash
kubectl auth can-i list secrets -n dev \
  --as=system:serviceaccount:dev:dev-ci-runner
```
*Expected Output: `no`*

### Test 3: Validate Secret Retrieval
The Service Account *is* allowed to load a specific secret if it knows its exact name. Verify this:
```bash
kubectl auth can-i get secrets -n dev \
  --as=system:serviceaccount:dev:dev-ci-runner
```
*Expected Output: `yes`*

### Test 4: Validate Namespace Escape Protection
Verify that the `dev-ci-runner` Service Account has no permissions in other namespaces (e.g. `kube-system` or `default`):
```bash
kubectl auth can-i list pods -n default \
  --as=system:serviceaccount:dev:dev-ci-runner
```
*Expected Output: `no`*

---

## Step 4: Audit active permissions

Run this query to locate which role bindings bind workloads to the `default` service accounts (a common security anti-pattern):
```bash
kubectl get rolebindings,clusterrolebindings --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.subjects[*].name}{"\n"}{end}' | grep "default"
```
*Note down any results matching bindings that link the `default` service account to high-privilege roles like `admin`, `edit`, or custom operator roles.*
