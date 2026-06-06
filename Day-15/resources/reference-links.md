# 📚 Day 15: Security Reference Links & Tools

Here is a curated collection of official documentation, production guides, hardening benchmarks, and security scanning tools to deepen your knowledge of Kubernetes security.

---

## 1. Official Kubernetes Documentation
* [Kubernetes RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
* [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
* [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
* [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
* [Admission Controllers Reference](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
* [Encrypting Secret Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)

---

## 2. Hardening Guides and Benchmarks
* [NSA/CISA Kubernetes Hardening Guidance (PDF)](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF)
* [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
* [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)

---

## 3. Policy Engines & Secret Operators
* [Kyverno: Kubernetes Native Policy Engine](https://kyverno.io/)
* [OPA Gatekeeper: Policy Controller for Kubernetes](https://open-policy-agent.github.io/gatekeeper/website/docs/)
* [External Secrets Operator (ESO)](https://external-secrets.io/)
* [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)

---

## 4. Static Scanning & Auditing Tools
* [kube-bench](https://github.com/aquasecurity/kube-bench): Checks cluster configuration against the CIS benchmark.
* [kubesec](https://kubesec.io/): Risk analysis tool for Kubernetes resources.
* [Trivy](https://github.com/aquasecurity/trivy): Vulnerability scanner for container images and Kubernetes manifests.
* [Cosign](https://github.com/sigstore/cosign): Container signing, verification, and storage in an OCI registry.
