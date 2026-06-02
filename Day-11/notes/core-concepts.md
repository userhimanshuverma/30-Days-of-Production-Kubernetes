# 📝 Day 11: Helm Deep Dive - Core Concepts & Architecture Reference

This reference manual provides a deep-dive exploration of Helm v3’s architecture, storage backends, templating engines, merge mechanics, and repository protocols.

---

## 1. Helm v3: Client-Only Architecture & Security Hardening

To appreciate Helm v3, we must understand the security flaws of **Helm v2**.

```
  HELM v2 (INSECURE)                                HELM v3 (SECURE & COMPLIANT)
  
  ┌──────────────┐                                  ┌──────────────┐
  │  Helm Client │                                  │  Helm Client │
  └──────┬───────┘                                  └──────┬───────┘
         │ (gRPC)                                          │ (Direct HTTPS)
         ▼                                                 │ Uses user's Kubeconfig
  ┌──────────────┐                                         │ RBAC restrictions
  │ Tiller Pod   │ (In-Cluster daemon                      ▼
  │ (Super-User) │  with cluster-admin rights)      ┌──────────────┐
  └──────┬───────┘                                  │  K8s API     │
         │ (Bypasses RBAC!)                         │  Server      │
         ▼                                          └──────────────┘
  ┌──────────────┐
  │  K8s API     │
  └──────────────┘
```

### The Tiller Security Vulnerability (Helm v2)
In Helm v2, the CLI did not talk to Kubernetes directly. It communicated via gRPC with **Tiller**, a daemon running inside the cluster.
* Tiller typically ran with `cluster-admin` privileges.
* When a developer executed `helm install`, Tiller created the resources.
* This bypassed Kubernetes RBAC! Even if a developer had permissions restricted to a single namespace, they could command Tiller to deploy resources to `kube-system` or mount host filesystems.
* Tiller did not authenticate clients by default, making it an easy target for attackers to control the entire cluster.

### The Helm v3 Solution
Helm v3 completely eliminated Tiller. The Helm client is now a standalone binary that compiles templates on your local machine and uses your local `kubeconfig` to execute commands against the Kubernetes API Server.
* **RBAC Compliance**: If your kubeconfig only allows you to create Pods in namespace `marketing`, then `helm install` will fail if the chart attempts to create a ClusterRole or write to `kube-system`.
* **Zero Overhead**: No daemon pods to run, monitor, patch, or secure.
* **Namespace-Scoped Releases**: Releases are tracked directly inside the namespace where they are deployed, rather than in Tiller's home namespace.

---

## 2. Release Storage Engine: Decoding the State

Where does Helm store its release records? It uses cluster-native **Secrets** (by default) or ConfigMaps.

Each time a chart is installed or upgraded, Helm creates a Secret in the same namespace as the release. The Secret's name matches the pattern:
`sh.helm.release.v1.<release-name>.v<revision-number>`

### Inside the Release Secret
Let's see what a release secret looks like:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sh.helm.release.v1.my-app.v1
  namespace: default
  labels:
    owner: helm
    name: my-app
    status: deployed
    version: "1"
type: helm.sh/release.v1
data:
  release: H4sICAAAAAAA/zNhcHAA... (Base64-encoded, Gzip-compressed JSON)
```

### How to Decode a Release Secret manually
If you ever need to inspect what Helm deployed without using the CLI, you can decode the release data using a shell pipeline:

```bash
# 1. Fetch the Base64 data from the Secret
# 2. Base64 decode it
# 3. Base64 decode it a second time (Helm encodes it twice)
# 4. Decompress using gzip
kubectl get secret sh.helm.release.v1.my-app.v1 -o jsonpath='{.data.release}' \
  | base64 --decode \
  | base64 --decode \
  | gunzip
```
The output is a large JSON structure containing:
* The original values passed (`chart.values`)
* The configuration templates (`chart.templates`)
* The exact generated Kubernetes manifests submitted to the API server (`manifest`)
* Metadata (creation timestamp, status, hooks run)

---

## 3. The Three-Way Strategic Merge Patch

When you run `helm upgrade`, Helm does not simply overwrite resources using `kubectl replace` (which is destructive and replaces the entire resource). Instead, it performs a **Three-Way Strategic Merge Patch**.

```
                   ┌───────────────────────────────────┐
                   │  1. Original Chart Manifest (v1)  │
                   └─────────────────┬─────────────────┘
                                     │
                                     ▼
   ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐
   │  Active Cluster   │ ◄─┤  Compare Engine   ├─► │   New Rendered    │
   │    State (v1.5)   │   └─────────┬─────────┘   │   Manifest (v2)   │
   └─────────┬─────────┘             │             └───────────────────┘
             │                       ▼
             │             ┌───────────────────┐
             └───────────► │  Calculated Patch │
                           └─────────┬─────────┘
                                     │
                                     ▼
                           ┌───────────────────┐
                           │   Apply to K8s    │
                           └───────────────────┘
```

The merge engine reconciles three states:
1. **The original manifest state** (what Helm generated in the previous revision).
2. **The current cluster state** (the actual live resource, which might have been modified by automated controllers like HPAs, or manually by an SRE running `kubectl edit`).
3. **The proposed new manifest state** (what the new Helm templates and values compile to).

### Scenario: Preserving Live Changes
Consider a deployment where you manually scaled replicas from 2 to 5 because of an unexpected traffic spike:
* **Original state (v1)**: `replicas: 2`
* **Live state**: `replicas: 5`
* **New state (v2)**: `replicas: 2` (default values unchanged)

Because Helm uses a three-way merge patch, it compares the new state with the original state. Since both show `replicas: 2`, Helm recognizes that *the template did not change this value*. It then compares with the live state (`replicas: 5`) and **preserves** the live state!
If it used a simple two-way replacement, it would overwrite the live state and scale the deployment back down to 2, causing an outage.

---

## 4. Advanced Templating Logic & Syntax

Go templates resolve expressions enclosed in `{{ }}`. Hyphens `{{-` and `-}}` strip preceding and trailing whitespaces and newlines.

### Context Scope (`.`)
The context object `.` is the active cursor. It changes depending on where you are in the template.
* In the root file, `.` points to the global scope.
* Inside a `with` block, the scope is reassigned to the selected key.
```yaml
# values.yaml
image:
  repository: nginx
  tag: latest

# template.yaml
{{- with .Values.image }}
image: "{{ .repository }}:{{ .tag }}" # Dot now refers to .Values.image
{{- end }}
```
* Inside a `range` block, the scope is reassigned to the current item in the iteration.

### The Global Variable (`$`)
If you change scopes with `with` or `range`, you lose access to root objects like `.Release.Name` or `.Values.global`. To access them, prefix the expression with `$` to refer back to the root scope:
```yaml
{{- range .Values.ports }}
- name: {{ .name }}
  containerPort: {{ .port }}
  labels:
    release-name: {{ $.Release.Name }} # Resolves correctly using global '$'
{{- end }}
```

### The `tpl` Function
The `tpl` function allows you to parse strings inside your `values.yaml` as Go templates. This is extremely useful for inserting release names or namespaces into configurations passed from outside:
```yaml
# values.yaml
configData:
  database_url: "jdbc:mysql://db-{{ .Release.Name }}:3306/db"

# templates/configmap.yaml
data:
  db_config: {{ tpl .Values.configData.database_url . | quote }}
```

### The `required` Function
Use `required` to validate that critical variables are provided during installation. If the value is empty, Helm aborts the template rendering and prints the error message:
```yaml
database:
  password: {{ required "A valid database.password is required!" .Values.database.password }}
```

---

## 5. Subcharts & Dependency Resolution

A chart can contain other charts, known as **subcharts**.

### Declaring Dependencies
Dependencies are defined in `Chart.yaml`:
```yaml
apiVersion: v2
name: my-app
version: 1.0.0
dependencies:
  - name: mariadb
    version: 11.x.x
    repository: https://charts.bitnami.com/bitnami
    condition: mariadb.enabled # Conditional activation
```

### Dependency Commands
* **`helm dependency list`**: Shows the status of all dependencies.
* **`helm dependency update`**: Resolves dependencies in `Chart.yaml` and downloads them as tarballs into the `charts/` folder. It also creates/updates `Chart.lock` to lock versions.
* **`helm dependency build`**: Recreates the `charts/` folder based strictly on `Chart.lock`.

### Overriding Subchart Values
A parent chart can override values in a subchart. In your parent chart's `values.yaml`, create a section matching the name of the subchart:
```yaml
# Parent values.yaml
mariadb:
  auth:
    database: app_db
    username: app_user
```
The child chart (`mariadb`) will receive these values as its local `.Values` context.

---

## 6. Helm and OCI Registries

Helm v3 supports using Open Container Initiative (OCI) registries (like Docker Hub, GitHub Packages, AWS ECR, Google Artifact Registry) to store and distribute charts, deprecating the need for separate index files (`index.yaml`) and web server setups.

```
 Traditional Charts                              OCI Registry Charts
 
 ┌──────────────────────┐                        ┌──────────────────────┐
 │ my-app-1.2.0.tgz     │                        │ registry.domain/chart│
 └──────────┬───────────┘                        └──────────┬───────────┘
            │                                               │
            ▼                                               ▼
 ┌──────────────────────┐                        ┌──────────────────────┐
 │ index.yaml           │                        │ OCI Manifest         │
 │ (Requires rebuild)   │                        │ (Built-in layer)     │
 └──────────────────────┘                        └──────────────────────┘
```

### OCI Release Commands
```bash
# 1. Login to the registry
helm registry login registry.domain.com -u admin -p $PASSWORD

# 2. Package the chart
helm package ./my-app

# 3. Push to OCI registry using the oci:// protocol
helm push my-app-1.2.0.tgz oci://registry.domain.com/helm-charts

# 4. Pull or install directly from OCI
helm install my-app oci://registry.domain.com/helm-charts/my-app --version 1.2.0
```

By pushing to OCI registries, Helm charts are treated exactly like container images. They are versioned, scanned, and RBAC-secured using the same container registry tooling already set up in your enterprise.
