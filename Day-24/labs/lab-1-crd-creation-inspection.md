# 🛠️ Lab 1: Custom Resource Definition (CRD) Creation & Inspection

## Overview
In this lab, you will register a Custom Resource Definition (CRD) to extend the Kubernetes API and deploy a Custom Resource (CR) instance representing a Postgres Database Cluster. You will learn how the API Server registers the new endpoint, handles validation, and presents fields through custom printer columns.

---

## Exercise 1: Registering the Custom Resource Definition

### 1. Apply the CRD Spec
Run the following command to apply the PostgresCluster CRD manifest to your cluster:
```bash
kubectl apply -f manifests/postgres-crd.yaml
```

*Expected Output:*
```text
customresourcedefinition.apiextensions.k8s.io/postgresclusters.database.production.k8s created
```

### 2. Verify registration in the API Server
Wait for the custom resource endpoint to become established and registered:
```bash
kubectl get crd postgresclusters.database.production.k8s
```

*Expected Output:*
```text
NAME                                         CREATED AT
postgresclusters.database.production.k8s     2026-06-15T14:21:23Z
```

### 3. Discover the API Group and Resources
Query the Kubernetes API Discovery endpoints to confirm the new resources are visible:
```bash
kubectl api-resources --api-group=database.production.k8s
```

*Expected Output:*
```text
NAME                SHORTNAMES          APIVERSION                     NAMESPACED   KIND
postgresclusters    pgdb,pgcluster      database.production.k8s/v1alpha1  true         PostgresCluster
```

Explain what happened: The API server registered a new path at `/apis/database.production.k8s/v1alpha1/...` and exposed custom shortnames (`pgdb`, `pgcluster`) which can now be used as shortcuts in `kubectl`.

---

## Exercise 2: Understanding Schema Validation

The CRD defines an OpenAPI v3 validation schema that requires `replicas`, `version`, and `storage` configuration. It enforces constraints on storage naming format (`Gi`, `Mi`, `Ti`) and sets boundaries on replica sizing.

### 1. Deploy a Valid Custom Resource
Apply the sample PostgresCluster CR:
```bash
kubectl apply -f manifests/postgres-cr.yaml
```

*Expected Output:*
```text
postgrescluster.database.production.k8s/prod-db-cluster created
```

### 2. Verify Output with Custom Printer Columns
Notice how `kubectl` reads fields directly from the spec and status without displaying full YAML content. This is powered by `additionalPrinterColumns` defined in our CRD spec:
```bash
kubectl get postgrescluster
```

*Expected Output:*
```text
NAME              REPLICAS   READY REPLICAS   VERSION   PHASE   AGE
prod-db-cluster   3                           15.2              12s
```
> **Note:** The `READY REPLICAS` and `PHASE` columns are empty because no controller is currently running to compute and update the Custom Resource's status.

### 3. Test API Validation Rules (Negative Testing)
Let's see what happens if we violate schema rules. Try to apply a resource with an invalid configuration:
```bash
kubectl apply -f - <<EOF
apiVersion: database.production.k8s/v1alpha1
kind: PostgresCluster
metadata:
  name: invalid-db
spec:
  replicas: 15        # Limit is 9
  version: "abc-15"   # Must match pattern '^[0-9]+(\.[0-9]+)?$'
  storage:
    size: "50GB"      # Must match pattern ending in Gi/Mi/Ti
    class: "standard"
EOF
```

*Expected Output (API Server Error):*
```text
The PostgresCluster "invalid-db" is invalid: 
* spec.replicas: Invalid value: 15: spec.replicas in body should be less than or equal to 9
* spec.version: Invalid value: "abc-15": spec.version in body should match '^[0-9]+(\.[0-9]+)?$'
* spec.storage.size: Invalid value: "50GB": spec.storage.size in body should match '^[0-9]+(Gi|Mi|Ti)$'
```

Key takeaway: Schema validation occurs entirely inside the `kube-apiserver` API admission chain BEFORE writing to `etcd`. It prevents corrupt or malformed inputs from ever hitting your operator.

---

## Exercise 3: Inspecting Resource Paths in etcd

If you have access to etcd or you run kubectl in raw mode, you can query the underlying resource format:
```bash
kubectl get --raw /apis/database.production.k8s/v1alpha1/namespaces/default/postgresclusters/prod-db-cluster | jq
```

This returns the precise JSON payload stored in `etcd`, demonstrating how Kubernetes extensibility makes your custom resources look, feel, and act exactly like native resources like Pods, Services, and Deployments.
