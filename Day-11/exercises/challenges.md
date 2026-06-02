# 🏆 Day 11: Helm Deep Dive - Exercises & Challenges

Complete these three production-level assignments to test your understanding of Helm templating, configuration engineering, and lifecycle management.

---

## Challenge 1: The Refactoring Challenge (Raw YAML to Helm)

### Objective
Convert a set of raw, environment-specific Kubernetes manifests into a single parameterized Helm Chart.

### Starting Scenario
In the [manifests/](manifests/) directory, you will find raw manifests for a microservice named `order-processor`.
These files contain hardcoded database credentials, different ingress hosts for dev and prod, and duplicate deployment definitions.

### Requirements:
1. Create a new chart directory under `exercises/` called `order-processor-chart`:
   ```bash
   helm create exercises/order-processor-chart
   ```
2. Clean all default boilerplate files in `templates/`.
3. Port the `order-processor` raw Deployment, Service, and Ingress manifests into the `templates/` folder.
4. Parameterize the following variables and place their defaults in `values.yaml`:
   * `replicaCount` (Dev: 1, Prod: 3)
   * `image.repository` and `image.tag`
   * `db.host` (Dev: `dev-db.internal`, Prod: `prod-db.internal`)
   * `db.port` (Default: `3306`)
   * `ingress.host` (Dev: `dev.orders.local`, Prod: `orders.local`)
5. Validate using `helm template`:
   ```bash
   helm template exercises/order-processor-chart
   ```

---

## Challenge 2: High Availability (HA) Hardening Challenge

### Objective
Modify your refactored chart to automatically apply enterprise high-availability settings when deploying to production.

### Requirements:
1. Add a **PodDisruptionBudget (PDB)** template (`templates/pdb.yaml`) that is only rendered if a configuration value `podDisruptionBudget.enabled` is `true`.
2. Add a **Pod Anti-Affinity** block in the `deployment.yaml` template so that if `affinity.enabled` is `true`, no two pods of this application are colocated on the same worker node (topology key: `kubernetes.io/hostname`).
3. Add resource limits and requests. They must be dynamic and rendered using `toYaml` and `nindent`.
4. Create a dedicated `values-production.yaml` overlay that configures:
   * `replicaCount: 3`
   * `podDisruptionBudget.enabled: true`
   * `affinity.enabled: true`
   * Strict CPU/Memory requests & limits.
5. Render the production configuration and verify the output:
   ```bash
   helm template order-processor exercises/order-processor-chart -f exercises/order-processor-chart/values-production.yaml
   ```

---

## Challenge 3: The Drift & Rollback Simulation

### Objective
Detect cluster drift, trigger a failed rollout, examine logs, and restore the cluster using Helm release states.

### Step-by-Step Instructions:
1. **Deploy Revision 1**: Install the `order-processor-chart` with stable settings.
2. **Introduce Drift**: Manually change the service port in the cluster using `kubectl`:
   ```bash
   kubectl edit svc order-processor-svc
   # Change port 80 to port 8080
   ```
3. **Detect the Drift**: Install the `helm diff` plugin if not already installed, and run a diff to see if it catches the manual changes:
   ```bash
   helm diff upgrade order-processor exercises/order-processor-chart
   ```
4. **Deploy a Broken Revision (Revision 2)**: Upgrade the release but change the image tag to a non-existent image (e.g., `order-processor:broken-v999`).
5. **Inspect the Failure**: Run commands to identify that the rollout is stuck and that pods are failing.
6. **Rollback**: Restore the cluster to the stable Revision 1 state. Verify that the manual drift is also reconciled by the strategic merge patch.
7. **Document the Logs**: Capture the output of `helm history` demonstrating a successful rollback and save it as a log snippet.
