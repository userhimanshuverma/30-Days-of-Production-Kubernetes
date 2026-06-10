# 🧪 Lab 1: Diagnose CrashLoopBackOff

## Objective
Learn how to identify and resolve a container stuck in a `CrashLoopBackOff` state due to startup configuration errors.

## Broken Environment
We will use the manifest [crashloop-db-missing.yaml](../manifests/crashloop-db-missing.yaml) which deploys a Python app that crashes if certain environment variables are missing.

---

## Step-by-Step Investigation

### 1. Apply the Broken Manifest
Apply the manifest to your cluster:
```bash
kubectl apply -f ../manifests/crashloop-db-missing.yaml
```

### 2. Inspect Pod Status
List the pods to view their status:
```bash
kubectl get pods
```

**Expected Output:**
```text
NAME                                 READY   STATUS             RESTARTS      AGE
payment-processor-597b489d89-9a12b   0/1     CrashLoopBackOff   2 (10s ago)   45s
```

### 3. Check Pod Events and Description
Retrieve structural information and event history:
```bash
kubectl describe pod -l app=payment-processor
```

**Key Section to Inspect:**
```text
State:          Waiting
  Reason:       CrashLoopBackOff
Last State:     Terminated
  Reason:       Error
  Exit Code:    1
```
The exit code is `1`, indicating an unhandled runtime exception/error.

### 4. Fetch Container Logs
Check the stdout and stderr streams of the failing container. Because the container is crashing, check the *previous* failed execution logs:
```bash
kubectl logs -l app=payment-processor --previous
```

**Expected Output:**
```text
Initializing Payment Processor v1.2.0...
FATAL CONFIG ERROR: Database credentials (DB_HOST, DB_PASSWORD) not injected!
Process exiting with code 1...
```
The logs explicitly point out the missing `DB_PASSWORD` configuration.

---

## Resolution Walkthrough

To resolve this issue, you must supply the missing environment variable configuration.

1. Open [crashloop-db-missing.yaml](../manifests/crashloop-db-missing.yaml).
2. Locate the `env` section of the container `processor`.
3. Add the missing `DB_PASSWORD` reference (in production, this would come from a Secret, but for this lab, we can inject a literal string value):
   ```yaml
   - name: DB_PASSWORD
     value: "supersecretpassword123"
   ```
4. Re-apply the manifest:
   ```bash
   kubectl apply -f ../manifests/crashloop-db-missing.yaml
   ```
5. Verify the pod starts successfully:
   ```bash
   kubectl get pods -w
   ```
   *The pod should transition from ContainerCreating to Running (READY 1/1).*
