# 🧪 Lab 2: Pod Security Standards & Security Contexts

This lab demonstrates how to enforce security boundaries on Pod resources inside a Namespace using Kubernetes' built-in Pod Security Admission (PSA) controller.

---

## Prerequisites
- A running Kubernetes cluster (v1.23+ required for stable Pod Security Admission).

---

## Step 1: Create security-labeled Namespaces

We will create two namespaces: one baseline and one restricted.

1. Review the manifests:
   - [manifests/pod-security-standards-baseline.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/pod-security-standards-baseline.yaml)
   - [manifests/pod-security-standards-restricted.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/pod-security-standards-restricted.yaml)
2. Apply the Namespace configurations:
   ```bash
   kubectl apply -f manifests/pod-security-standards-baseline.yaml
   kubectl apply -f manifests/pod-security-standards-restricted.yaml
   ```

Verify the namespaces and labels are active:
```bash
kubectl get namespaces --show-labels | grep -E "baseline|restricted"
```

---

## Step 2: Test Baseline namespace limits (Simulate security violation)

The `baseline` standard blocks privileged pods. Let's attempt to run a pod that shares the host network and runs in privileged mode.

1. Write a temporary privileged pod spec to a file:
   ```yaml
   # privileged-pod.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: host-exploit-pod
     namespace: baseline-namespace
   spec:
     hostNetwork: true
     containers:
       - name: exploit
         image: alpine
         command: ["sleep", "3600"]
         securityContext:
           privileged: true
   ```
2. Apply the pod:
   ```bash
   kubectl apply -f privileged-pod.yaml
   ```
3. Observe the rejection message returned directly by the API Server admission controller:
   *Expected output: Error from server (Forbidden): ... violates PodSecurity "baseline:latest": hostNetwork: true, privileged: true ...*

---

## Step 3: Test Restricted namespace limits

Next, let's attempt to deploy a standard Nginx image in the `restricted-namespace` namespace.

1. Create a simple Nginx pod manifest:
   ```yaml
   # simple-nginx.yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: basic-nginx
     namespace: restricted-namespace
   spec:
     containers:
       - name: web
         image: nginx
   ```
2. Run it:
   ```bash
   kubectl apply -f simple-nginx.yaml
   ```
3. Read the rejection message:
   *Expected output: Error from server (Forbidden): ... violates PodSecurity "restricted:latest": runAsNonRoot != true (pod or container "web" must run as non-root), allowPrivilegeEscalation != false, capabilities.drop != ALL, readOnlyRootFilesystem != true...*

The built-in admission controller blocked the deployment because standard Nginx runs as root, allows privilege escalation, doesn't drop kernel capabilities, and writes log files directly to its local root filesystem.

---

## Step 4: Deploy a Hardened Pod in the Restricted Namespace

To run workloads in a hardened restricted namespace, we must define a robust `securityContext`.

1. Review [manifests/secure-app-security-context.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/secure-app-security-context.yaml). This deployment uses:
   - `nginxinc/nginx-unprivileged:alpine` (runs as UID 10001, port 8080).
   - Pod level: `runAsNonRoot: true`, `runAsUser: 10001`, `seccompProfile: {type: RuntimeDefault}`.
   - Container level: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities: {drop: [ALL]}`.
   - Volume: Mounts a RAM-backed `emptyDir` on `/tmp` because Nginx requires writing cache/logs. Since the root FS is read-only, `/tmp` handles temp files in-memory.
2. Apply the configuration (patching the target namespace to `restricted-namespace` for testing):
   ```bash
   # We can deploy this manifest in any restricted namespace. Let's create it inside the production namespace, but first let's label production to be restricted
   kubectl create namespace production || true
   kubectl label namespace production pod-security.kubernetes.io/enforce=restricted --overwrite
   kubectl label namespace production pod-security.kubernetes.io/warn=restricted --overwrite
   
   kubectl apply -f manifests/secure-app-security-context.yaml
   ```
3. Verify the deployment:
   ```bash
   kubectl get deployments -n production
   kubectl get pods -n production
   ```
   *The pods should successfully spin up to a `Running` state because they comply fully with the restricted standards.*

4. Verify the root filesystem is indeed read-only:
   ```bash
   # Find the pod name
   POD_NAME=$(kubectl get pods -n production -l app=secure-web -o jsonpath='{.items[0].metadata.name}')
   
   # Attempt to write a file to root directory /
   kubectl exec -n production $POD_NAME -c web-server -- touch /test-write.txt
   ```
   *Expected Output: `touch: /test-write.txt: Read-only file system`*

5. Verify that writing to the `/tmp` RAM mount is allowed:
   ```bash
   kubectl exec -n production $POD_NAME -c web-server -- touch /tmp/test-write.txt
   ```
   *Expected Output: No error (command succeeds).*
