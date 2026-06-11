# 🧪 Lab 6: Multi-Environment Promotion Workflows

In enterprise systems, you do not deploy changes directly to production. An application must pass verification in Staging before promotion. In a GitOps world, environment promotion is achieved by moving configurations through Git branches or, preferably, **Git directories** using Kustomize overlays.

In this lab, we will build a production-grade multi-environment directory layout using Kustomize.

---

## 📂 The Directory Structure

We will structure our configurations under `gitops/` using a **base-and-overlay** pattern:

```text
gitops/
├── base/
│   ├── deployment.yaml      # General deployment structure
│   ├── service.yaml         # Service definition
│   └── kustomization.yaml   # Declares base resources
└── overlays/
    ├── staging/
    │   ├── kustomization.yaml  # Points to base, updates namespace & labels
    │   └── patches.yaml        # Staging-specific overrides (e.g., replicas = 2)
    └── production/
        ├── kustomization.yaml  # Points to base, updates namespace & labels
        └── patches.yaml        # Production-specific overrides (e.g., replicas = 5)
```

---

## Step 1: Create the Base manifests
We will set up the base files inside the `gitops/base/` folder. These files define the generic blueprint of the application without hardcoded environments.

### `gitops/base/deployment.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing-app
spec:
  template:
    metadata:
      labels:
        app: billing-app
    spec:
      containers:
        - name: web
          image: nginx:alpine
          ports:
            - containerPort: 80
```

### `gitops/base/service.yaml`
```yaml
apiVersion: v1
kind: Service
metadata:
  name: billing-app
spec:
  ports:
    - port: 80
      targetPort: 80
  selector:
    app: billing-app
```

### `gitops/base/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
```

---

## Step 2: Create the Staging Overlay
The Staging overlay imports the base files and applies modifications (patches) specific to the staging environment.

### `gitops/overlays/staging/patches.yaml`
In staging, we want 2 replicas and an environment flag:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing-app
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: web
          env:
            - name: APP_ENV
              value: "staging"
```

### `gitops/overlays/staging/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: staging-env
resources:
  - ../../base
patches:
  - path: patches.yaml
```

---

## Step 3: Create the Production Overlay
In production, we need higher reliability, so we will scale the deployment to 5 replicas.

### `gitops/overlays/production/patches.yaml`
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing-app
spec:
  replicas: 5
  template:
    spec:
      containers:
        - name: web
          env:
            - name: APP_ENV
              value: "production"
```

### `gitops/overlays/production/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod-env
resources:
  - ../../base
patches:
  - path: patches.yaml
```

---

## Step 4: Validate Overlay Rendering Locally
Before committing files to Git, you should render Kustomize overlays locally to confirm the final YAML is generated correctly:

```bash
# Render staging configuration
kustomize build gitops/overlays/staging

# Render production configuration
kustomize build gitops/overlays/production
```

**Verify the outputs:**
* Check that the staging output contains `namespace: staging-env` and `replicas: 2`.
* Check that the production output contains `namespace: prod-env` and `replicas: 5`.

---

## Step 5: The Promotion Workflow

To promote a new container image from Staging to Production, you execute the following GitOps workflow:

1. **Deploy to Staging:** The CI pipeline runs on a merge to the developer branch, building image `v2.1.0`. The CI pipeline commits this change directly to `gitops/overlays/staging/kustomization.yaml` (or updates an image tag override).
2. **Reconciliation:** Flux or ArgoCD detects the change and updates the Staging environment.
3. **Run Smoke/Integration Tests:** SRE team runs automatic validation tests against staging-env endpoint.
4. **Create Promotion PR:** If tests pass, an automated script (or SRE) opens a Git Pull Request (PR) merging the changes from Staging overlay into `gitops/overlays/production/kustomization.yaml`.
5. **Peer Review & Approve:** Senior engineers review the PR diff, check testing logs, and click "Merge".
6. **Deploy to Production:** The production GitOps controller detects the merge on main config branch, pulls the update, and reconciles the production cluster to the identical tested image tag.
