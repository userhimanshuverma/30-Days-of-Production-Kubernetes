# Lab 2: Installing Linkerd

## Goal
Install the Linkerd service mesh in your Kubernetes cluster, run checks, and install its dashboard extension.

---

## Step 1: Install the Linkerd CLI

1.  Download the CLI installer script:
    ```bash
    curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
    ```
2.  Add the binary directory to your path (Linux/macOS):
    ```bash
    export PATH=$HOME/.linkerd2/bin:$PATH
    ```
3.  Verify the CLI works:
    ```bash
    linkerd version
    ```

---

## Step 2: Validate Cluster Context

Run pre-flight checks to ensure the cluster matches Linkerd's network requirements:
```bash
linkerd check --pre
```
*Look for all green checkmarks (`[ok]`) validating api-server availability, RBAC scope, and scheduling nodes.*

---

## Step 3: Install CRDs and Control Plane

Linkerd separates its Custom Resource Definitions from the main control plane controller.

1.  Install the required CRDs first:
    ```bash
    linkerd install --crds | kubectl apply -f -
    ```
2.  Install the core control plane components:
    ```bash
    linkerd install | kubectl apply -f -
    ```
3.  Wait for the installation to finish and execute checks:
    ```bash
    linkerd check
    ```
    *This runs tests on the control plane namespace components and verifies mTLS readiness.*

---

## Step 4: Install Linkerd Viz Extension

Linkerd does not bundle observability by default. We install the `linkerd-viz` extension to add metrics and dashboards.

1.  Apply the customized viz configuration manifest:
    ```bash
    kubectl apply -f linkerd/linkerd-viz.yaml
    ```
2.  Alternatively, deploy the complete viz extensions using the CLI:
    ```bash
    linkerd viz install | kubectl apply -f -
    ```
3.  Check the status of the viz components:
    ```bash
    linkerd viz check
    ```

---

## Step 5: Access the Dashboard

Launch the web GUI locally to explore traffic graphs:
```bash
linkerd viz dashboard
```
*This command runs a secure local proxy and prints a loopback URL (e.g. `http://localhost:50750`) to access the metrics dashboard.*
