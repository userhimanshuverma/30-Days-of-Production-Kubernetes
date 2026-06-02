# 🚨 Day 11: Helm Deep Dive - Troubleshooting & Incident Playbook

This runbook contains diagnoses, resolutions, and preventions for the 10 most common failures encountered during production Helm operations.

---

## Playbook Index
1. [Template Rendering & Indentation Failures](#1-template-rendering--indentation-failures)
2. [Nil Pointer Evaluations (Missing Values)](#2-nil-pointer-evaluations-missing-values)
3. [Release Stuck in PENDING_INSTALL / PENDING_UPGRADE](#3-release-stuck-in-pending_install--pending_upgrade)
4. [Immutable Field Upgrades (Selectors Mismatch)](#4-immutable-field-upgrades-selectors-mismatch)
5. [Rollback Failure (Database Schema Incompatibility)](#5-rollback-failure-database-schema-incompatibility)
6. [Subchart Version Conflicts](#6-subchart-version-conflicts)
7. [Admission Webhook Validation Mismatch](#7-admission-webhook-validation-mismatch)
8. [OCI Registry Pull Authentication Failures](#8-oci-registry-pull-authentication-failures)
9. [Release History Secret Size Limit Exceeded](#9-release-history-secret-size-limit-exceeded)
10. [Out-of-Sync Configuration Drift](#10-out-of-sync-configuration-drift)

---

## 1. Template Rendering & Indentation Failures

### Symptoms
`helm install` or `helm template` command fails with syntax errors:
```text
Error: YAML parse error on my-app/templates/deployment.yaml: line 14: did not find expected key
```

### Root Cause
Improper indentation spacing or incorrect use of spacing hyphens in Go templates (e.g., mixing `indent` and `nindent`, or misplaced whitespace control hyphens like `{{-`).

### Investigation
Render the template and look at the line number mentioned:
```bash
helm template my-app ./my-app --debug
```
The `--debug` flag prints the generated YAML even if it is invalid, showing exactly where alignment is broken.

### Resolution
Ensure that `nindent` value matches the required indentation level:
```yaml
# In values.yaml:
resources:
  limits:
    cpu: 100m

# In templates/deployment.yaml (incorrect):
resources:
{{ toYaml .Values.resources }} # renders at column 0!

# In templates/deployment.yaml (correct):
resources:
  {{- toYaml .Values.resources | nindent 10 }} # correctly indents under spec.template.spec.containers
```

### Prevention
* Run `helm lint` in your pre-commit hooks and CI pipelines.
* Prefer `nindent` (which adds a newline and then indents) over `indent` to prevent trailing whitespace syntax errors.

---

## 2. Nil Pointer Evaluations (Missing Values)

### Symptoms
```text
Error: render error in "my-app/templates/deployment.yaml": template: my-app/templates/deployment.yaml:12:32: executing "my-app/templates/deployment.yaml" at <.Values.image.repository>: nil pointer evaluating interface {}
```

### Root Cause
The template refers to a nested value (e.g., `.Values.image.repository`) but the parent key (`image:`) is missing or undefined in your `values.yaml` file.

### Investigation
Locate the line inside the template and verify if default values are defined:
```bash
grep -n "image" ./my-app/values.yaml
```

### Resolution
* Initialize parent structures in `values.yaml`:
  ```yaml
  image:
    repository: nginx
    tag: stable
  ```
* In templates, wrap checks in dynamic conditionals or fallbacks:
  ```yaml
  image: "{{ .Values.image.repository | default "nginx" }}:{{ .Values.image.tag | default "latest" }}"
  ```

### Prevention
* Use the `required` function to block installs on critical unset parameters.
* Implement JSON schema validation (`values.schema.json`) to enforce required keys before compilation.

---

## 3. Release Stuck in PENDING_INSTALL / PENDING_UPGRADE

### Symptoms
```text
Error: HELM UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress
```

### Root Cause
A deployment crashed or timed out mid-process. Helm marked the state as `PENDING_INSTALL` or `PENDING_UPGRADE` to prevent concurrent modifications, blocking subsequent commands.

### Investigation
Check release history:
```bash
helm history my-release
```
Locate the row showing the status `pending-install` or `pending-upgrade`.

### Resolution
1. **Force Rollback (Recommended)**:
   Rollback to the last known healthy revision:
   ```bash
   helm rollback my-release <last-stable-revision>
   ```
2. **Delete the stuck release Secret**:
   If a rollback fails because the CLI refuses to run, delete the secret tracking the stuck deployment:
   ```bash
   kubectl delete secret sh.helm.release.v1.my-release.v3
   ```
   Now run your upgrade command again.

### Prevention
* Always set the `--timeout` parameter during upgrades to abort the deploy rather than hanging indefinitely.
* Use `--wait` to ensure resources are fully rolled out before marking the revision as successful.

---

## 4. Immutable Field Upgrades (Selectors Mismatch)

### Symptoms
```text
Error: UPGRADE FAILED: Deployment.apps "my-app-deploy" is invalid: spec.selector: Invalid value: field is immutable
```

### Root Cause
You updated the selector labels in your template files. Kubernetes does not allow updating selector labels (`spec.selector.matchLabels`) on existing Deployments or StatefulSets because it breaks matching with active ReplicaSets.

### Investigation
Compare active selectors with template definitions:
```bash
kubectl get deployment my-app-deploy -o jsonpath='{.spec.selector}'
helm template my-app ./my-app --show-only templates/deployment.yaml
```

### Resolution
* **Safe Path**: Rollback your chart selector label modifications. If you need new labels, add them to `metadata.labels` instead (which are mutable).
* **Destructive Path (Recreate)**: If you must change selectors, delete the deployment manually before upgrading (this causes temporary downtime):
  ```bash
  kubectl delete deployment my-app-deploy --cascade=orphan
  helm upgrade my-app ./my-app
  ```

### Prevention
Avoid parameterizing selector labels. Keep selector maps static and minimal throughout the lifecycle of the application.

---

## 5. Rollback Failure (Database Schema Incompatibility)

### Symptoms
After running `helm rollback my-release 4`, the rollback succeeds at the Helm level, but the application pods crash continuously with database connection or column migration errors.

### Root Cause
Helm reverts Kubernetes manifests, but it does **not** revert external data, state, or database schemas. If Revision 5 ran SQL schema migrations (e.g., dropping a column), rolling back the application container to Revision 4 causes database schema incompatibility.

### Investigation
Read container logs:
```bash
kubectl logs -l app=my-app --tail=100
```
Look for DB initialization or connection-level crashes.

### Resolution
1. Immediately restore the database schema backup to match the previous version.
2. Deploy a hotfix release that contains compatible code instead of performing a simple rollback.

### Prevention
* Implement backward-compatible database schemas.
* Follow the expand-contract pattern: never drop a database field until the older application versions are fully decommissioned.

---

## 6. Subchart Version Conflicts

### Symptoms
```text
Error: dependency mariadb not found in charts/ directory
```

### Root Cause
The `Chart.lock` and downloaded dependencies are missing or out of sync after updating `Chart.yaml`.

### Investigation
```bash
helm dependency list ./my-app
```
Look for "missing" or "conflict" statuses in the table output.

### Resolution
Rebuild dependencies:
```bash
helm dependency update ./my-app
```
This downloads matching subchart tarballs into `charts/` and updates `Chart.lock`.

### Prevention
Check `Chart.lock` into your Git repository to ensure consistent dependency builds across environments.

---

## 7. Admission Webhook Validation Mismatch

### Symptoms
```text
Error: UPGRADE FAILED: admission webhook "validation.gatekeeper.sh" denied the request: container resources limits are missing
```

### Root Cause
An admission controller in the cluster (e.g., OPA Gatekeeper, Kyverno) blocked the deployment because the rendered manifests violated compliance rules (e.g., missing resource limits, running as root).

### Investigation
Run the template dry-run and inspect generated resources:
```bash
helm template my-app ./my-app > output.yaml
# Manually inspect output.yaml for security configuration blocks
```

### Resolution
Update your `values.yaml` to include compliant configurations (e.g., resource requests or securityContext block) and upgrade:
```yaml
# values.yaml
resources:
  limits:
    cpu: 100m
    memory: 128Mi
```

### Prevention
Integrate policy validation scanners (e.g., `conftest` or `polaris`) into your deployment pipeline.

---

## 8. OCI Registry Pull Authentication Failures

### Symptoms
```text
Error: pull chart from localhost:5001/helm-charts/my-app:1.0.0: unauthorized: authentication required
```

### Root Cause
The runner or workstation shell does not have valid authentication tokens to pull charts from the private OCI registry.

### Investigation
Check docker credentials or local registry status:
```bash
helm registry login localhost:5001
```

### Resolution
Log in to the registry before running the deploy:
```bash
echo $REGISTRY_PASSWORD | helm registry login localhost:5001 -u admin --password-stdin
```

### Prevention
For Kubernetes deployments that pull subcharts dynamically at runtime, ensure the CI pipeline runs registry login checks before compiling the chart.

---

## 9. Release History Secret Size Limit Exceeded

### Symptoms
```text
Error: UPGRADE FAILED: Secret "sh.helm.release.v1.my-app.v50" is invalid: data: Too long: must have at most 1048576 bytes
```

### Root Cause
Kubernetes Secrets have a hard limit of 1MB. If your Helm chart has massive templates (e.g., embedding large configurations, binary files, or dashboards directly inside ConfigMaps) and a long history, the secret data exceeds 1MB.

### Investigation
Check size of templates folder:
```bash
du -sh ./my-app/templates
```
Identify large files embedded in ConfigMaps.

### Resolution
1. Limit release history size to prune old records:
   ```bash
   helm upgrade my-app ./my-app --history-max 10
   ```
2. Decouple binary blobs and large static files. Store them in Object Storage (e.g., S3) or use Kubernetes PersistentVolumes instead of embedding them in Helm ConfigMaps.

### Prevention
Configure `--history-max` globally in your CD pipeline.

---

## 10. Out-of-Sync Configuration Drift

### Symptoms
Deployments fail with resource conflict errors:
```text
Error: UPGRADE FAILED: rendered manifests contain a resource that already exists. Unable to apply: ServiceAccount "my-app-sa" in namespace "default"
```

### Root Cause
A resource was created manually using `kubectl apply -f` or by a different deployment pipeline, and it was not tracked in Helm's Release Secret.

### Investigation
Check ownership labels on the conflicting resource:
```bash
kubectl get sa my-app-sa -o yaml
```
Look for the `meta.helm.sh/release-name` label. If it is missing, Helm did not create this resource.

### Resolution
1. **Adopt the Resource**: Add Helm ownership labels to the resource manually:
   ```bash
   kubectl label sa my-app-sa app.kubernetes.io/managed-by=Helm
   kubectl annotate sa my-app-sa meta.helm.sh/release-name=my-release meta.helm.sh/release-namespace=default
   ```
2. Delete the manually created resource if it is safe to recreate.

### Prevention
Avoid applying manifests manually. All shared resources should be managed exclusively via the Helm chart or GitOps pipeline.
