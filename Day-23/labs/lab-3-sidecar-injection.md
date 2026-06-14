# Lab 3: Configure Sidecar Injection

## Goal
Enable automatic sidecar proxy injection on namespaces, deploy workload services, and verify that the sidecars are injected and running.

---

## Step 1: Label Namespace for Istio Injection

By default, Istio does not touch any workload unless its namespace contains the correct trigger label.

1.  Enable automatic sidecar injection in the `default` namespace:
    ```bash
    kubectl label namespace default istio-injection=enabled --overwrite
    ```
2.  Verify the label is applied:
    ```bash
    kubectl get namespace default --show-labels
    ```

---

## Step 2: Deploy Workloads

Deploy the frontend and backend deployments, along with their associated services.

1.  Apply the workloads from the `manifests/` folder:
    ```bash
    kubectl apply -f manifests/services.yaml
    kubectl apply -f manifests/frontend-deployment.yaml
    kubectl apply -f manifests/backend-v1-deployment.yaml
    kubectl apply -f manifests/backend-v2-deployment.yaml
    ```
2.  Monitor pod creation:
    ```bash
    kubectl get pods -w
    ```
    *Observe that the container status reads `0/2` -> `1/2` -> `2/2`, indicating that two containers are starting in each pod.*

---

## Step 3: Inspect Pod Container Structure

1.  Inspect the details of a running backend pod:
    ```bash
    kubectl get pod -l app=backend-service,version=v1 -o jsonpath='{.spec.containers[*].name}'
    ```
    *Expected Output:*
    ```
    application istio-proxy
    ```
    *This confirms `istio-proxy` is running alongside the `application` container.*

2.  Examine the init container that set up the network redirection:
    ```bash
    kubectl get pod -l app=backend-service,version=v1 -o jsonpath='{.spec.initContainers[*].name}'
    ```
    *Expected Output:*
    ```
    istio-init
    ```

---

## Step 4: Examine Proxy Logs

Check the bootstrap sequence of the sidecar container:
```bash
kubectl logs -l app=backend-service,version=v1 -c istio-proxy --tail=50
```
*Look for log entries confirming connection to Pilot (istiod) on port 15012 and successful loading of the local listener configuration.*
