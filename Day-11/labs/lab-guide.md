# 🛠️ Day 11: Helm Deep Dive - Hands-On Labs

This lab guide contains 10 sequential, production-focused labs to master Helm operations, package design, and troubleshooting.

---

## Prerequisites
* A running Kubernetes cluster (e.g., Kind, Minikube, or custom cluster).
* Local terminal access with `kubectl` configured.

---

## 🟢 Lab 1: Install Helm CLI

Install the Helm client binary on your workstation and verify its configuration.

### Installation Commands:
* **macOS (Homebrew)**: `brew install helm`
* **Linux (Debian/Ubuntu)**:
  ```bash
  curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
  sudo apt-get install apt-transport-https --yes
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
  sudo apt-get update
  sudo apt-get install helm -y
  ```
* **Windows (Chocolatey)**: `choco install kubernetes-helm`
* **Windows (Winget)**: `winget install Helm.Helm`

### Verify the Installation:
Run the version command to verify that Helm is installed and check its build information:
```bash
helm version
```

### Expected Output:
```text
version.BuildInfo{Version:"v3.12.0", GitCommit:"c61330239917b26c318d85f130d17774c0b40900", GitTreeState:"clean", GoVersion:"go1.20.3"}
```

---

## 🟢 Lab 2: Create Your First Chart

Generate the standard skeleton structure for a new Helm chart and clean the boilerplates.

### Step 1: Generate the Chart Skeleton
Navigate to your workspace and generate a new chart named `my-web-app`:
```bash
helm create my-web-app
```

### Step 2: Inspect the Directories
List the generated structure:
```bash
ls -R my-web-app
```
Notice the pre-generated files inside `templates/` (e.g., `deployment.yaml`, `service.yaml`, `hpa.yaml`, `ingress.yaml`).

### Step 3: Clean Boilerplate Templates
We want to learn by building templates from scratch. Delete the default files inside the templates directory:
```bash
rm -rf my-web-app/templates/*.yaml
rm -rf my-web-app/templates/*.txt
```

---

## 🟢 Lab 3: Build Custom Templates

Create dynamic configurations for a Deployment and Service by importing raw YAML and defining parameters.

### Step 1: Create a Deployment Template
Create `my-web-app/templates/deployment.yaml` with the following content:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-deploy
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: web
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: {{ .Values.service.port }}
```

### Step 2: Create a Service Template
Create `my-web-app/templates/service.yaml` with the following content:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-svc
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.port }}
      protocol: TCP
  selector:
    app: {{ .Release.Name }}
```

---

## 🟢 Lab 4: Configure values.yaml

Establish the configuration parameters contract by defining default properties.

### Step 1: Open values.yaml
Replace the entire content of `my-web-app/values.yaml` with the following overrides:
```yaml
# Default values for my-web-app.
replicaCount: 2

image:
  repository: nginx
  tag: 1.25.1

service:
  type: ClusterIP
  port: 80
```

### Step 2: Perform a Dry-Run Render
Verify that the values are correctly injected without actually deploying to the cluster:
```bash
helm template my-web-app ./my-web-app
```

### Expected Output:
```yaml
# Source: my-web-app/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: release-name-deploy
...
spec:
  replicas: 2
...
      containers:
        - name: web
          image: "nginx:1.25.1"
...
# Source: my-web-app/templates/service.yaml
apiVersion: v1
kind: Service
...
  type: ClusterIP
```

---

## 🟢 Lab 5: Deploy the Release

Install the chart on your Kubernetes cluster and inspect release states.

### Step 1: Deploy the Chart
Install the chart and name the release `web-dev`:
```bash
helm install web-dev ./my-web-app --namespace default
```

### Expected Output:
```text
NAME: web-dev
LAST DEPLOYED: Tue Jun 02 19:40:00 2026
NAMESPACE: default
STATUS: deployed
REVISION: 1
TEST SUITE: None
```

### Step 2: Inspect Kubernetes Resources
```bash
kubectl get deployments,pods,services -l app=web-dev
```
You should see 2 nginx pods spinning up, named after the release.

### Step 3: Check Helm Release State
```bash
helm list
```

---

## 🟢 Lab 6: Upgrades & Revisions

Update configurations dynamically and track release revisions.

### Step 1: Upgrade to a NodePort Service & 3 Replicas
Run the upgrade command, passing value overrides using the `--set` flag:
```bash
helm upgrade web-dev ./my-web-app \
  --set replicaCount=3 \
  --set service.type=NodePort
```

### Expected Output:
```text
NAME: web-dev
LAST DEPLOYED: Tue Jun 02 19:42:00 2026
NAMESPACE: default
STATUS: deployed
REVISION: 2
```

### Step 2: Validate the Changes
```bash
kubectl get service web-dev-svc
```
The Service type is now `NodePort` instead of `ClusterIP`.

### Step 3: Check History
```bash
helm history web-dev
```

### Expected Output:
```text
REVISION    UPDATED                     STATUS      CHART               APP VERSION DESCRIPTION
1           Tue Jun  2 19:40:00 2026    superseded  my-web-app-0.1.0    1.25.1      Install complete
2           Tue Jun  2 19:42:00 2026    deployed    my-web-app-0.1.0    1.25.1      Upgrade to 3 replicas
```

---

## 🟡 Lab 7: Perform a Rollback

Revert deployment configurations to previous revisions.

### Step 1: Deploy a Broken Revision
Let's simulate a broken release by deploying an image tag that does not exist:
```bash
helm upgrade web-dev ./my-web-app --set image.tag=invalid-tag-999
```
Check the pods:
```bash
kubectl get pods -w
```
You will see the new pods stuck in `ErrImagePull` or `ImagePullBackOff`.

### Step 2: Execute a Rollback
Revert back to the stable state (Revision 2):
```bash
helm rollback web-dev 2
```

### Expected Output:
```text
Rollback release web-dev to 2...
Rollback was successful. Happy Helming!
```

### Step 3: Verify Cluster Status
Check the history:
```bash
helm history web-dev
```
You will see a **Revision 4** created, indicating a rollback to Revision 2. The broken pods are immediately terminated, and the stable pods are restored.

---

## 🟡 Lab 8: Packaging the Chart

Archive a chart source directory into a standardized distribution bundle.

### Step 1: Configure Metadata
Open `my-web-app/Chart.yaml` and update the version information:
```yaml
apiVersion: v2
name: my-web-app
description: A production grade Nginx web server
type: application
version: 1.0.0
appVersion: "1.25.1"
```

### Step 2: Package the Chart
Run the packager command:
```bash
helm package ./my-web-app
```

### Expected Output:
```text
Successfully packaged chart and saved it to: /workspace/my-web-app-1.0.0.tgz
```

---

## 🔴 Lab 9: Publish Chart to a Repository

Configure a static repository or push the chart bundle to an OCI Registry.

### Scenario: Pushing to a Local OCI Registry
For this lab, we will run a local Docker registry and push our packaged chart directly to it.

### Step 1: Start a Registry Pod locally
If you don't have a container registry, spin up a local registry in Docker:
```bash
docker run -d -p 5001:5000 --name local-registry registry:2
```

### Step 2: Authenticate and Login
```bash
helm registry login localhost:5001 -u user -p password --insecure
```

### Step 3: Push the Package
Push the tarball to your registry using the OCI scheme:
```bash
helm push my-web-app-1.0.0.tgz oci://localhost:5001/helm-charts
```

### Expected Output:
```text
Pushed: localhost:5001/helm-charts/my-web-app:1.0.0
Digest: sha256:4b834857b28db72bb7f7fef7b57fb4a36fcd8ef9e18b879383929beabed99abc
```

---

## 🔴 Lab 10: Deploy Production Stack (Kafka Override)

Perform a deployment of a real-world infrastructure component using repository updates and custom values.

### Step 1: Add Bitnami Repository
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### Step 2: Write Custom Overrides File
Create a file named `kafka-prod-values.yaml`:
```yaml
replicaCount: 3
persistence:
  enabled: true
  size: 20Gi
resources:
  limits:
    cpu: "2"
    memory: 2Gi
  requests:
    cpu: "500m"
    memory: 1Gi
metrics:
  kafka:
    enabled: true
```

### Step 3: Install Kafka Chart with Overrides
```bash
helm install prod-kafka bitnami/kafka -f kafka-prod-values.yaml --create-namespace --namespace kafka
```

### Step 4: Validate Release Deployment
```bash
helm status prod-kafka -n kafka
```
Observe the NOTES.txt output detailing how to access bootstrap servers, and verify that 3 replica statefulsets are deployed.
