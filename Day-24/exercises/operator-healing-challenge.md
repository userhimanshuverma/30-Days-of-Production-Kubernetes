# 🏆 Day 24 Challenge: Operator Healing & CRD Troubleshooting

## Scenario Description
An engineering team deployed a custom Operator to manage legacy caches. However, when they applied the Custom Resource Definition (CRD), they encountered API server errors. After bypassing the CRD issues by modifying the schema manually, they realized the operator failed to reconcile changes, scale commands using `kubectl scale` failed, and finalizers were stuck blocking resource deletions.

Your challenge is to analyze the broken manifests in [broken-crd-challenge.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-24/exercises/broken-crd-challenge.yaml), identify the errors, fix them, deploy the corrected versions, and verify that all features work properly.

---

## Challenge Steps

### 1. Analyze and Debug `broken-crd-challenge.yaml`
Open the [broken-crd-challenge.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-24/exercises/broken-crd-challenge.yaml) file. You will notice three core bugs:
* **Syntax/Schema Mismatch:** In the OpenAPI specification validation block, the patterns or formatting specifications might be invalid.
* **Subresource Path Misalignment:** The scale subresource paths (`specReplicasPath` and `statusReplicasPath`) are mapped incorrectly compared to the actual location in the schema structure.
* **Validation Pattern Bypass:** The validation for memory sizing allows values that crash the operator engine behind the scenes (e.g., standard sizing unit is `Mi`/`Gi`, but it permits arbitrary letters like `256XX`).

### 2. Perform the Fixes
Modify [broken-crd-challenge.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-24/exercises/broken-crd-challenge.yaml) directly or write a corrected file to resolve:
1. The incorrect path mappings inside `spec.versions[0].subresources.scale`.
2. The regular expression pattern inside `spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.memory.pattern` to only accept integers followed by `Mi`, `Gi`, or `Ti`.
3. The names matching casing rules (such as plural and singular casing inconsistencies).

### 3. Deploy to Kind or Minikube
Verify your configurations by deploying:
```bash
# Apply the corrected CRD
kubectl apply -f exercises/broken-crd-challenge.yaml

# Inspect validation rules by attempting to apply an invalid payload (it should be rejected!)
kubectl apply -f - <<EOF
apiVersion: cache.production.k8s/v1alpha1
kind: CacheCluster
metadata:
  name: broken-instance
spec:
  replicas: 12        # This exceeds maximum limit of 9
  memory: "256XX"     # Invalid unit format
EOF
```
*Expected Result:* The API Server MUST reject the request with validation errors.

### 4. Verify Scaling Extensibility
Apply a valid Cache Custom Resource instance:
```bash
kubectl apply -f - <<EOF
apiVersion: cache.production.k8s/v1alpha1
kind: CacheCluster
metadata:
  name: production-cache
spec:
  replicas: 3
  memory: "512Mi"
EOF
```
Now test subresource integration using `scale`:
```bash
kubectl scale --replicas=5 cachecluster/production-cache
```
Check if the custom resource spec is successfully updated:
```bash
kubectl get cachecluster production-cache -o yaml
```

---

## Success Criteria
1. The CRD deploys successfully without API server parser failures.
2. The API Server actively blocks invalid inputs (invalid replica counts, invalid memory strings).
3. The command `kubectl scale` successfully scales the replica spec of the resource without throwing "scale subresource not found" errors.
