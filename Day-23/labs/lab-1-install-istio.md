# Lab 1: Installing Istio via istioctl & Operator

## Goal
Install the Istio service mesh in your cluster using the `istioctl` binary and the `IstioOperator` configuration profile.

---

## Step 1: Download and Install `istioctl`

1.  Download the Istio installation bundle (version `1.18.0` is used for today's lab):
    ```bash
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.18.0 sh -
    ```
2.  Move into the Istio directory:
    ```bash
    cd istio-1.18.0
    ```
3.  Add the `istioctl` client to your PATH (Linux/macOS):
    ```bash
    export PATH=$PWD/bin:$PATH
    ```
    *(For Windows, add the `bin` directory to your System Environment PATH).*

4.  Verify the installation:
    ```bash
    istioctl version
    ```

---

## Step 2: Pre-flight Verification

Verify if your Kubernetes cluster satisfies Istio's deployment prerequisites:
```bash
istioctl x precheck
```
*Expected Output:*
```
✔ No issues found when checking the cluster. Istio is safe to install or upgrade.
```

---

## Step 3: Deploy Istio using the Operator Profile

We will use the customized `istio-operator.yaml` file located in the `istio/` directory to configure resource bounds, replicas, and telemetry limits.

1.  Navigate back to the Day 23 directory:
    ```bash
    cd ../Day-23
    ```
2.  Install the control plane using the operator manifest:
    ```bash
    istioctl install -f istio/istio-operator.yaml -y
    ```
    *Expected Output:*
    ```
    ✔ Istio core installed
    ✔ Istiod installed
    ✔ Ingress gateways installed
    ✔ Installation complete
    ```

---

## Step 4: Verify Deployment Components

1.  Inspect the running pods inside the `istio-system` namespace:
    ```bash
    kubectl get pods -n istio-system
    ```
    *Expected Output:*
    ```
    NAME                                    READY   STATUS    RESTARTS   AGE
    istiod-7b968bc7f-8rwx9                  1/1     Running   0          45s
    istiod-7b968bc7f-abcde                  1/1     Running   0          45s
    istio-ingressgateway-695c8c6fbc-xyz12   1/1     Running   0          42s
    ```
2.  Verify the HorizontalPodAutoscaler is bound to `istiod`:
    ```bash
    kubectl get hpa -n istio-system
    ```

---

## 🚨 Troubleshooting & Diagnostics
*   **Symptom**: Installation times out or pods are stuck in `Pending`.
    *   *Cause*: Inefficient node resources or insufficient RAM (e.g. Minikube/Kind cluster CPU limits are too low).
    *   *Diagnostic*: Run `kubectl describe pod -n istio-system -l app=istiod` and search for scheduling events.
    *   *Resolution*: Increase your local cluster memory allocation to at least 4GB and 4 CPUs.
