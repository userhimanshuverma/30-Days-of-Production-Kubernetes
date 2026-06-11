# 🧠 Exercise 2: Building a Promotion Pipeline

## 🎯 Objective
Design a directory-based promotion layout using Kustomize to safely promote container images from Staging to Production, maintaining environmental isolation.

---

## 🛠️ The Challenge

You need to deploy a microservice called `inventory-service` across two environments: Staging and Production.

### Requirements:

1. **Common Base:**
   * Create a base folder containing a Deployment and Service for `inventory-service`.
   * The container must use image `nginx:1.25.1`.

2. **Staging Environment Overlay:**
   * Target namespace: `inventory-staging`.
   * Replicas: `1`.
   * Environment variables: `ENV_NAME=staging`, `API_DEBUG=true`.
   * Container CPU limit: `100m`, Memory limit: `128Mi`.

3. **Production Environment Overlay:**
   * Target namespace: `inventory-production`.
   * Replicas: `4` (with RollingUpdate surge configuration: maxSurge=50%, maxUnavailable=0).
   * Environment variables: `ENV_NAME=production`, `API_DEBUG=false`.
   * Container CPU limit: `500m`, Memory limit: `512Mi`.

4. **Promotion Script:**
   * Write a bash script (`promote.sh`) that takes a container tag as an argument (e.g. `./promote.sh 1.25.2`), updates the Staging overlay image tag, waits for validation, and prints the git diff that would be submitted to Production.

---

## 📝 Directory Skeleton

You should organize your directory structure inside `exercises/` as:
```text
exercises/exercise-2/
├── base/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── staging/
    │   ├── kustomization.yaml
    │   └── patches.yaml
    └── production/
        ├── kustomization.yaml
        └── patches.yaml
```

---

## 🏆 Evaluation Checklist

To verify your layout:
* Run `kustomize build overlays/staging` and verify that the limits are `128Mi` and replicas is `1`.
* Run `kustomize build overlays/production` and verify that the limits are `512Mi` and replicas is `4`.
* Execute `./promote.sh 1.25.3` and inspect the console output to verify that Kustomize overlays are updated programmatically.
