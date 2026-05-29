# 📚 Recommended Readings & Resources

Dive deeper into cloud-native configuration management and advanced security policies using the references below.

---

## 1. Kubernetes Official Documentation
* [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/): Official guide on managing configuration data.
* [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/): Official guide on handling sensitive workloads.
* [KMS v2 Envelope Encryption](https://kubernetes.io/docs/tasks/administer-cluster/kms-provider/): Detailed instructions on configuring KMS v2 to encrypt Secrets at rest in `etcd`.

---

## 2. External Secret Management Systems
* [External Secrets Operator (ESO) Docs](https://external-secrets.io/): Installation guides, provider specifications (AWS, Azure, GCP, HashiCorp Vault), and API references.
* [HashiCorp Vault K8s Integration](https://developer.hashicorp.com/vault/docs/platform/k8s): Learn how the Vault Agent Injector functions, authentication flows, and templates configuration.

---

## 3. Security Frameworks & Policies
* [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html): Best practices for securing configurations and restricting pod service account tokens.
* [Twelve-Factor App (Factor III - Config)](https://12factor.net/config): The core philosophy of separating configuration from code in modern cloud architectures.
