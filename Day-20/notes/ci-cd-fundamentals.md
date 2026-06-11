# 📔 Kubernetes CI/CD Fundamentals: Push vs. Pull Architectures

Continuous Integration (CI) and Continuous Delivery/Deployment (CD) are often spoken of as a single entity ("CI/CD"). However, in the cloud-native ecosystem, they represent two completely different operational boundaries. 

This note covers the design differences between **Push-based** and **Pull-based** deployments and why pushing manifests from typical CI engines is an anti-pattern at scale.

---

## 🏗️ The Operational Boundaries

In a clean Kubernetes platform architecture:
* **Continuous Integration (CI) is code-centric.** It ends at the container registry. Its goal is to compile code, run tests, build a secure container image, and push it to a registry.
* **Continuous Delivery/Deployment (CD) is config-centric.** It begins at the registry and ends in the running cluster. Its goal is to reconcile desired state (in Git) with live state (in Kubernetes).

---

## 🚫 The Push Model (Traditional CI/CD)

In a push-based model, the pipeline executor (GitHub Actions, GitLab CI, Jenkins) is responsible for pushing state updates directly to the Kubernetes API server.

```
[ Git Push ] ──> [ CI Runner ] ──( executes: kubectl apply -f manifests/ )──> [ K8s API ]
```

### Execution Flow:
1. Developer pushes code to Git.
2. CI server starts a runner.
3. Runner builds, tests, and tags the container image (e.g., `my-app:v1.1.0`).
4. Runner runs templating (like `helm template` or `kustomize build`).
5. Runner authenticates with the target cluster using a high-privilege `kubeconfig` credential stored in CI secrets.
6. Runner executes `kubectl apply` or `helm upgrade`.

### Why this breaks at scale:
* **The "Blast Radius" of Secrets:** The CI runner holds cluster-admin (or near cluster-admin) keys. If a developer compromises the CI runner configuration (e.g., via a malicious dependency or an engineered PR injection), your entire production infrastructure is exposed.
* **Firewall Openings:** Push pipelines require your Kubernetes API server to be accessible from the internet or CI runner network pools. Exposing the Kube-API server increases the cluster's attack surface.
* **No Reconciliation or Self-Healing:** The push command is a one-time operation. If the pods crash two hours later or a human deletes a deployment manually, the CI pipeline is oblivious. It only checks compliance at the moment of execution.
* **Rate-limiting and Concurrency:** If 50 developer teams trigger pipelines at the same time, the API server can become rate-limited, and deployments can fail due to concurrency locks or network hiccups in the runner.

---

## 🔄 The Pull Model (GitOps CD)

In a pull-based model, an agent (operator) running inside the Kubernetes cluster is responsible for pulling configurations from Git and applying them locally.

```
[ Git Push ] ──> [ CI Server ] ──> [ Image Registry ]
                         │
                  (Updates Git Tag)
                         │
                         ▼
                  [ Git Config Repo ] <──( Pulls & Reconciles )── [ GitOps Agent in Cluster ]
```

### Execution Flow:
1. Developer pushes code to Git.
2. CI pipeline builds the image and pushes it to the Container Registry.
3. CI pipeline updates a separate **Config Repository** containing the Kubernetes manifests (e.g., updates the tag from `v1.0.0` to `v1.1.0` in a Kustomize file).
4. The GitOps Controller running *inside* the cluster polls the Config Repo (or receives a Git webhook).
5. The Controller detects a difference between the desired state in Git and the live state in the cluster.
6. The Controller pulls the manifests and applies them locally using the in-cluster service account credentials.

### Why this is superior in production:
* **Zero Shared Credentials:** No external system holds your cluster certificates or administrative keys. All deployments happen using the cluster's native RBAC (`ServiceAccount`).
* **Private API Servers:** Your Kubernetes API server can remain completely private within a secure Virtual Private Cloud (VPC), with no public ingress required for CI tools.
* **Continuous Reconciliation (Drift Correction):** The controller checks state compliance every few minutes (or seconds). If a configuration drift is detected (e.g., a developer scales down a replica set manually), the controller automatically overwrites the cluster state back to the Git source of truth.
* **Git as the Single Source of Truth:** Your Git history acts as a cryptographic audit log. Every single change to production can be traced to a commit hash, a pull request, and an approved author.
* **Easy Disaster Recovery:** If a cluster is deleted, you can spin up a new empty cluster, install the GitOps agent, point it at the Git Config Repo, and watch the entire platform reconstruct itself automatically in minutes.

---

## ⚙️ Push-to-Pull Transition Checklist

If you are migrating an enterprise platform from a push model to GitOps:

1. **Decouple repositories:** Separate application code repos from infrastructure configuration repos.
2. **Remove kubeconfig from CI/CD variables:** Revoke all API tokens currently stored in Jenkins, GitLab, or GitHub secrets.
3. **Establish tag propagation:** Modify the end of the CI pipeline to push a Git commit (or open a PR) in the config repo containing the updated tag, instead of triggering a deploy.
4. **Enforce branch protection:** Restrict writes to the config repo's main branch. All changes must go through Pull Request approvals (peer reviews).
