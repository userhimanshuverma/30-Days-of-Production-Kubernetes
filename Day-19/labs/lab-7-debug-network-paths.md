# 🧪 Lab 7: Debug Network Paths & Ephemeral Containers

## Objective
Learn how to use network utility pods (like `netshoot`) and **ephemeral debug containers** (`kubectl debug`) to capture traffic and diagnose connectivity issues in raw environments.

## Prerequisite
- A running Kubernetes cluster (v1.23+ supporting Ephemeral Containers).

---

## Step-by-Step Investigation

### Method 1: Using the Standalone Debug Pod
We can run our Swiss Army knife network toolkit pod in the same namespace as the target applications.

1. Deploy the toolkit:
   ```bash
   kubectl apply -f ../manifests/debugging-toolkit.yaml
   ```
2. Exec into the pod:
   ```bash
   kubectl exec -it debug-toolkit -- /bin/bash
   ```
3. Test connectivity to standard services:
   ```bash
   # Test DNS
   nslookup order-service
   
   # Trace route paths
   traceroute order-service
   
   # Perform raw request test
   curl -Iv http://order-service:80
   ```
4. Exit the container.

---

### Method 2: Attaching an Ephemeral Debug Container
In highly secured production environments, application images are often built using `distroless` templates (minimal, containing zero debugging tools, not even a shell). 
We can dynamically attach a debugging container sharing the namespaces and process space of the running application.

1. Let's assume we have a pod running under deployment `order-api-v1-xxx`. Locate its exact pod name:
   ```bash
   kubectl get pods -l app=order-api-v1
   ```
2. Run `kubectl debug` to attach a debug container utilizing the `nicolaka/netshoot` image:
   ```bash
   kubectl debug -it <order-api-pod-name> --image=nicolaka/netshoot --target=order-api
   ```
   *Note:* `--target` allows sharing the process namespace of the main application container, enabling you to inspect local file handles and threads.

3. Inside this shell, run diagnostics:
   *   View processes running in the application container:
       ```bash
       ps aux
       ```
   *   Audit local TCP network sockets:
       ```bash
       netstat -tulpn
       ```
   *   Capture raw loopback or network interface packets:
       ```bash
       tcpdump -c 10 -i any port 80
       ```
4. Exit the debugger shell. The ephemeral container will terminate, leaving the target container untouched.
