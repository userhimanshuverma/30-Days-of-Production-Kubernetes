# 🧪 Day 7 Lab Guide: Hands-On Configuration & Secrets Management

This lab guide walks you through deploying, verifying, rotating, and troubleshooting configuration management patterns in a Kubernetes environment.

---

## Lab 1: ConfigMaps (Creation, Env Injection, Volume Mounts)

### Objective
Create and consume a ConfigMap using environment variables and volume mounts.

### Step 1.1: Deploy the ConfigMap
Apply the ConfigMap manifest containing properties, JSON, and flat key-value pairs:
```bash
kubectl apply -f [manifests/01-configmap.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-07/manifests/01-configmap.yaml)
```

**Expected Output:**
```
configmap/app-config created
```

Verify that the ConfigMap was created with the correct data entries:
```bash
kubectl describe configmap app-config
```

### Step 1.2: Deploy Environment Variable Injection
Deploy the payment processor deployment configured to inject properties:
```bash
kubectl apply -f [manifests/03-deployment-env-injection.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-07/manifests/03-deployment-env-injection.yaml)
```

Check the status of the rollout:
```bash
kubectl rollout status deployment/payment-processor-env
```

### Step 1.3: Verify Injected Variables
Find one of the active pods:
```bash
POD_NAME=$(kubectl get pods -l app=payment-processor -o jsonpath='{.items[0].metadata.name}')
```

Run `env` inside the pod to verify the ConfigMap keys are available as OS environment variables:
```bash
kubectl exec $POD_NAME -- env | grep -E "LOG_LEVEL|DB_MAX_CONNECTIONS"
```

**Expected Output:**
```
LOG_LEVEL=INFO
DB_MAX_CONNECTIONS=20
```

---

## Lab 2: Secrets (Base64 encoding and Volume Mounting)

### Objective
Deploy a Kubernetes Secret and mount it as a read-only volume with restricted Unix file permissions.

### Step 2.1: Deploy the Secret
Apply the Secret manifest containing base64 credentials:
```bash
kubectl apply -f [manifests/02-secret.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-07/manifests/02-secret.yaml)
```

### Step 2.2: Deploy Volume Mounted Workload
Apply the deployment configured with `defaultMode: 0400` mounts and running as user `10001`:
```bash
kubectl apply -f [manifests/04-deployment-volume-mount.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-07/manifests/04-deployment-volume-mount.yaml)
```

### Step 2.3: Verify File Permissions
Find the active pod:
```bash
VOL_POD=$(kubectl get pods -l app=payment-processor -o jsonpath='{.items[1].metadata.name}')
```

Check the mounted file structure:
```bash
kubectl exec $VOL_POD -- ls -l /etc/app/secrets
```

**Expected Output:**
```
-r--------    1 10001    10001            5 May 29 23:30 db-user
-r--------    1 10001    10001           24 May 29 23:30 db-password
```
> [!NOTE]
> The permissions show `-r--------`, which maps to `0400` in octal (read-only by the owner only).

Read the credential values:
```bash
kubectl exec $VOL_POD -- cat /etc/app/secrets/db-password
```

---

## Lab 3: Vault Agent Webhook Sidecar Injection (Dry-run / Concept Validation)

### Objective
Configure a deployment to retrieve credentials dynamically from a Vault instance using Vault Agent Injector.

### Step 3.1: Examine Webhook Deployment
Open the manifest [manifests/05-vault-agent-injector.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-07/manifests/05-vault-agent-injector.yaml) and inspect the annotations.

To run this in an active cluster, the Vault operator must be installed:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm install vault hashicorp/vault --set "injector.enabled=true"
```

### Step 3.2: Verify Vault Service Account
Apply the manifest to configure the service account:
```bash
kubectl apply -f [manifests/05-vault-agent-injector.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-07/manifests/05-vault-agent-injector.yaml)
```

Verify that the Vault Agent successfully mounts the shared memory volume `/vault/secrets/` by inspecting the mutated Pod status:
```bash
kubectl get pod -l app=payment-processor
```
If the Pod fails startup or stays in `Init` state, use:
```bash
kubectl logs <pod-name> -c vault-agent-init
```

---

## Lab 4: External Secrets Operator (ESO) Setup

### Objective
Configure ESO to pull a secret from an external API and map it to a native K8s Secret.

### Step 4.1: Install ESO
Deploy External Secrets Operator using Helm:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
    -n external-secrets --create-namespace
```

### Step 4.2: Apply SecretStore & ExternalSecret
Configure the authentication store and mappings:
```bash
kubectl apply -f [manifests/06-external-secrets.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-07/manifests/06-external-secrets.yaml)
```

### Step 4.3: Monitor Sync status
Verify that the sync reconciled successfully:
```bash
kubectl get externalsecret payment-db-secret
```

Verify that the native Secret was created:
```bash
kubectl get secret payment-database-credentials -o yaml
```

---

## Lab 5: Troubleshooting Configuration Failures

Let's debug a failing deployment.

### Scenario: The Pod is Stuck in `CreateContainerConfigError`
1. Create a pod that references a missing ConfigMap:
   ```bash
   kubectl run failing-pod --image=nginx --env=MY_VAR=configmapRef:non-existent-cm:key
   ```
2. Diagnose:
   ```bash
   kubectl get pods
   ```
   You will see:
   ```
   NAME          READY   STATUS                         RESTARTS   AGE
   failing-pod   0/1     CreateContainerConfigError     0          10s
   ```
3. Run:
   ```bash
   kubectl describe pod failing-pod
   ```
   In the events output at the bottom, notice:
   ```
   Warning  Failed   3s  kubelet  Error: configmap "non-existent-cm" not found
   ```
4. Fix: Create the ConfigMap or delete the failing pod.
   ```bash
   kubectl delete pod failing-pod
   ```
