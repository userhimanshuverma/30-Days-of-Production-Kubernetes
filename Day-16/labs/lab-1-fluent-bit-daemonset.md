# Lab 1: Configure & Deploy Fluent Bit DaemonSets

In this lab, you will deploy a Fluent Bit logging agent as a `DaemonSet` on every node of your Kubernetes cluster. You will configure it to tail local node paths, parse CRI logs, and filter metadata using Kubernetes endpoints.

---

## Prerequisites
* A running local Kubernetes cluster (Minikube, Kind, or similar)
* `kubectl` CLI installed and configured.

---

## Step 1: Create the Logging Namespace

To isolate observability workloads, we always deploy logging tools to a dedicated namespace:

```bash
kubectl create namespace logging
```

---

## Step 2: Review and Apply Fluent Bit Configurations

Before running the DaemonSet, we must load the configurations into the cluster. This is managed via a `ConfigMap` defining:
1. `SERVICE` configurations for buffer paths and port triggers.
2. `INPUT` configs specifying where logs live.
3. `PARSER` expressions for container runtimes.
4. `FILTER` rules for Kubernetes annotations.

Apply the configurations:

```bash
kubectl apply -f ../manifests/fluent-bit-configmap.yaml
```

Verify that the configmap was created:
```bash
kubectl describe configmap fluent-bit-config -n logging
```

---

## Step 3: Deploy the Fluent Bit Agent DaemonSet

The DaemonSet mounts critical host directories (`/var/log/containers` and `/var/log/pods`) into the agent containers so they can access stdout files.

Apply the DaemonSet manifest (which includes the service account and necessary cluster roles):

```bash
kubectl apply -f ../manifests/fluent-bit-daemonset.yaml
```

---

## Step 4: Verify Deployment and Node Coverage

Since Fluent Bit is a DaemonSet, Kubernetes schedules exactly **one pod per node**.

1. Verify that all logging pods are running:
   ```bash
   kubectl get pods -n logging -l k8s-app=fluent-bit -o wide
   ```

2. Inspect the startup logs of one of the agents:
   ```bash
   kubectl logs -n logging daemonset/fluent-bit --tail=50
   ```
   *Expected Output Check:* Look for lines indicating initialization of plugins and database engines:
   ```text
   [2026/06/07 12:00:00] [ info] [engine] started; database=/var/log/fluent-bit/flb_kube.db
   [2026/06/07 12:00:00] [ info] [filter:kubernetes:kubernetes.0] K8s client: Service Account Token loaded
   [2026/06/07 12:00:00] [ info] [sp] integrity checks passed
   ```

---

## Step 5: Verify Local HTTP Monitoring Endpoint

Fluent Bit runs a internal HTTP statistics dashboard on port `2020` to expose metrics like records processed, inputs, and outputs.

1. Port-forward the dashboard of a running pod:
   ```bash
   # Replace with your actual fluent-bit pod name
   kubectl port-forward -n logging fluent-bit-xxxxx 2020:2020
   ```

2. Query the storage/buffer metrics in another terminal:
   ```bash
   curl http://localhost:2020/v1/storage
   ```
   *Example JSON response:*
   ```json
   {
     "storage": {
       "path": "/var/log/fluent-bit/buffer",
       "sync": "normal",
       "checksum": "off"
     }
   }
   ```
   This metrics endpoint is commonly scraped by Prometheus to trigger alerts on backpressure or buffer exhaustion.
