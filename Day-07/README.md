# ðŸ“– Day-07 - ConfigMaps, Secrets and Environment Management
### ðŸ·ï¸ PHASE 1 - FOUNDATIONS OF CLOUD-NATIVE SYSTEMS

> **TL;DR:** Configuration separation, secrets protection, and External Secret Operator integration.

---

## ðŸŽ¯ Learning Objectives
By the end of this day, you will be able to:
1. Explain the architectural concepts of **ConfigMaps, Secrets and Environment Management**.
2. Troubleshoot and solve primary issues related to this domain.
3. Configure, deploy, and inspect manifests in a running Kubernetes environment.
4. Relate these concepts to enterprise and production environment scaling challenges.

---

## ðŸ“ Core Concepts
*Theoretical deep dives, diagrams, and reference guides can be found in the [notes/](notes/) directory.*

* **Key Topic 1:** Core definition and architectural positioning.
* **Key Topic 2:** Communication path and workflow dependencies.
* **Key Topic 3:** Common design trade-offs and operational best practices.

---

## ðŸ› ï¸ Hands-On Lab Walkthrough
*Step-by-step guides can be found in the [labs/](labs/) directory.*

### Prerequisites
* A running Kubernetes Cluster (Kind, Minikube, or custom dev cluster)
* kubectl CLI installed and configured.

### Lab Steps
1. **Apply configurations:**
   `ash
   kubectl apply -f manifests/
   `
2. **Inspect and Verify:**
   `ash
   kubectl get all -n default
   `
3. **Validate logs and debug states:**
   `ash
   kubectl logs <pod-name>
   `

---

## âš¡ Production Considerations and Hardening
*Deep operational notes are located in the [production-notes/](production-notes/) directory.*

* **Security:** Pod security, RBAC scope limits, and resource quotas.
* **Performance:** Resource limits and horizontal autoscaling rules.
* **Reliability:** Liveness, readiness, and startup probe definitions.

---

## ðŸš¨ Troubleshooting and Debugging Playbook
*Comprehensive troubleshooting runbooks can be found in the [troubleshooting/](troubleshooting/) directory.*

| Common Error | Likely Cause | Solution & Diagnostics Command |
|---|---|---|
| Error/CrashLoopBackOff | Configuration mismatch or missing dependency | kubectl describe pod / kubectl logs |
| ImagePullBackOff | Private registry credential error or typo | Check Secret definition and image tags |

---

## ðŸ† Daily Assignment and Challenge
*Details and code challenges can be found in the [exercises/](exercises/) directory.*

* **Challenge:** Implement the scenario details inside the exercise manifest, verify using local kind cluster and capture logs demonstrating deployment success.

---

## ðŸ“š References and Recommended Reading
*See details in [resources/](resources/) directory.*

* [Kubernetes Documentation](https://kubernetes.io/docs/)
* Production guidelines and reference blogs.
