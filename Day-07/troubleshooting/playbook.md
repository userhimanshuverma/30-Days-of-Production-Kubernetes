# 🚨 Kubernetes Configuration & Secret Management Troubleshooting Playbook

This playbook provides actionable diagnostic runbooks for resolving common issues with ConfigMaps, Secrets, environment variables, and external secret sync engines.

---

## Scenario 1: Missing Environment Variables / Pod CrashLoopBackOff

### Symptoms
* Pod transitions into `CreateContainerConfigError` or `CrashLoopBackOff`.
* `kubectl describe pod` shows:
  ```
  Warning  Failed      3s (x2 over 12s)  kubelet  Error: configmap "app-settings" not found
  ```
* Pod logs show error: `Process exited with code 1: API_KEY is not defined`.

### Root Cause
1. **Referencing non-existent resource:** The Pod manifest contains a `valueFrom.configMapKeyRef` or `valueFrom.secretKeyRef` pointing to a ConfigMap or Secret that does not exist in the target namespace.
2. **Missing Key:** The ConfigMap or Secret exists, but the specific key referenced in the `key` field is missing.

### Investigation
```bash
# 1. Describe the pod to see direct error messages from Kubelet
kubectl describe pod <pod-name> -n <namespace>

# 2. Check if the ConfigMap/Secret exists in the namespace
kubectl get configmap app-settings -n <namespace>
kubectl get secret app-secrets -n <namespace>

# 3. Check keys inside the resource
kubectl get configmap app-settings -o jsonpath='{.data}' -n <namespace>
```

### Resolution
* Create the missing ConfigMap or Secret resource, or update the key.
* Ensure keys in the Pod manifest match the names in the data resource exactly (keys are case-sensitive).

### Prevention
* Implement schema validation in CI/CD pipelines.
* Use Kustomize or Helm to bundle resources, ensuring dependent ConfigMaps/Secrets are generated and packaged alongside the workload deployments.

---

## Scenario 2: Mounted ConfigMap/Secret File Update Not Reflected

### Symptoms
* A ConfigMap or Secret mounted as a Volume was updated in the API server, but the application container continues to operate with stale configurations.

### Root Cause
1. **Using `subPath` volume mounts:** Files mounted using `subPath` are **not** updated dynamically by Kubelet when the underlying resource changes. Kubelet only tracks updates for entire directory mounts.
2. **Kubelet Sync Delay:** There is a delay (up to 1 minute, based on Kubelet sync period and config cache TTL) before Kubelet writes the update to the pod directory.
3. **Application Cache:** The file was updated on the container disk, but the application loaded the config into memory during startup and does not monitor disk changes.

### Investigation
```bash
# 1. Check if the file was updated on the node disk inside the container
kubectl exec -it <pod-name> -c <container-name> -n <namespace> -- cat /etc/config/settings.yaml

# 2. Inspect the volume definition in the pod specification to check for subPath
kubectl get pod <pod-name> -o yaml -n <namespace> | grep -A 5 volumeMounts
```

### Resolution
* **If subPath is used:** You must restart the pod to pull the latest changes:
  ```bash
  kubectl rollout restart deployment/<deployment-name> -n <namespace>
  ```
* **If subPath is NOT used:** Implement an in-memory watch in the application code, or use a controller like **Reloader** to automatically trigger a rolling restart of the Deployment when the ConfigMap/Secret hash changes.

### Prevention
* Avoid using `subPath` for files that require dynamic, non-disruptive rotation.
* Standardize on directory-based volume mounts.

---

## Scenario 3: External Secrets Operator (ESO) Sync Failure

### Symptoms
* An `ExternalSecret` resource is created, but the native Kubernetes Secret is never generated.
* `kubectl get externalsecret` shows `Sync Error` or `SecretSynced = False`.

### Root Cause
1. **Authentication Failure:** The `SecretStore` credentials (IAM Role, API token, ServiceAccount token) do not have permissions to read from the cloud Key Vault.
2. **Missing Cloud Secret:** The secret path or name specified in the `ExternalSecret` manifest does not exist in AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager.
3. **Network/Proxy Block:** The ESO controller is blocked from accessing the cloud provider's API endpoints by a NetworkPolicy or egress firewall.

### Investigation
```bash
# 1. Describe the ExternalSecret resource to view status conditions
kubectl describe externalsecret <es-name> -n <namespace>

# 2. Get the SecretStore status to verify authentication
kubectl describe secretstore <store-name> -n <namespace>

# 3. Check the logs of the External Secrets Operator controller pod
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```

### Resolution
* Verify the IAM policies attached to the EKS/GKE Service Account (IRSA / Workload Identity).
* Ensure the secret name and key mappings in the `ExternalSecret` manifest are correct.
* Confirm that network security groups permit outbound traffic to the cloud metadata and Secret Manager APIs.

### Prevention
* Bind alerts to the `external_secrets_sync_status` metric in Prometheus to immediately alert operators when a sync fails.

---

## Scenario 4: Vault Sidecar Injection Failure

### Symptoms
* Workload Pod remains in `Pending` or crashes with `Init:CrashLoopBackOff` or `Init:0/1`.
* Vault agent sidecar container is not injected.
* Application container fails to startup because `/vault/secrets/` directory does not exist.

### Root Cause
1. **Mutating Webhook Blocked:** The Vault Agent Injector webhook service is down, or cluster-to-service communication is blocked.
2. **Missing Annotations:** The Deployment manifest does not contain the required Vault annotations (e.g., `vault.hashicorp.com/agent-inject: "true"`).
3. **Vault ServiceAccount Auth Failed:** The Kubernetes service account assigned to the Pod is not authorized in Vault's K8s authentication backend, preventing the Init container from retrieving a token.

### Investigation
```bash
# 1. Describe the pod to see if the Init container failed
kubectl describe pod <pod-name> -n <namespace>

# 2. View the logs of the Vault Agent Init container
kubectl logs <pod-name> -c vault-agent-init -n <namespace>

# 3. Verify annotations on the deployment template
kubectl get deployment <deployment-name> -o yaml -n <namespace> | grep vault.hashicorp.com
```

### Resolution
* Add the required annotations to the Pod template spec (not the Deployment level spec).
* Configure Vault's Kubernetes auth role to bind the target namespace and ServiceAccount name:
  ```bash
  vault write auth/kubernetes/role/app-role \
      bound_service_account_names=<sa-name> \
      bound_service_account_namespaces=<namespace> \
      policies=app-policy \
      ttl=24h
  ```

### Prevention
* Maintain a central registry of Helm charts that enforce correct Vault annotations based on service configuration flags.
