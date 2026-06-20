# Hardening GitHub Actions Workflows for Production Kubernetes

A security guidelines checklist for securing GitHub Actions CI/CD pipelines against supply-chain attacks.

---

## 🔒 1. Apply Least-Privilege Permissions
By default, GitHub runner tokens (`GITHUB_TOKEN`) may have write access to repository contents. Explicitly scope permissions at the job or workflow level.

```yaml
# Enforce read-only permissions on GITHUB_TOKEN by default
permissions:
  contents: read
  packages: write  # Limit write only to package pushes
  id-token: write  # Required for OpenID Connect (OIDC) auth
```

---

## 🔑 2. Eliminate Long-Lived Cloud Keys (Use OIDC)
Do not store permanent credentials like `AWS_ACCESS_KEY_ID` in repository secrets. Instead, configure OpenID Connect (OIDC) to exchange short-lived tokens with the cloud provider (AWS/GCP/Azure) dynamically.

### Example: AWS OIDC Integration Spec
```yaml
steps:
  - name: Configure AWS Credentials via OIDC
    uses: aws-actions/configure-aws-credentials@v2
    with:
      role-to-assume: arn:aws:iam::123456789012:role/github-actions-k8s-deployer
      aws-region: us-east-1
      audience: sts.amazonaws.com
```

---

## 📌 3. Pin Actions to Specific Commit SHAs
Version tags (like `@v3`) are mutable and can be overwritten by compromised third-party extensions. Use full commit hashes for third-party actions to prevent code injection.

```yaml
# Before:
uses: actions/checkout@v3

# After (Hardened):
uses: actions/checkout@8ade135a41bc03ea155e62e844d188df1fd717b9 # Pin v3.5.2
```

---

## 🛡️ 4. Integrate Container Image Scanning (Trivy)
Scan built Docker images for CVE vulnerabilities and misconfigurations prior to pushing them to registries.

```yaml
steps:
  - name: Run Trivy Vulnerability Scanner
    uses: aquasecurity/trivy-action@master
    with:
      image-ref: 'ghcr.io/company/fastapi-ai-service:latest'
      format: 'table'
      exit-code: '1' # Break the build if CRITICAL vulnerabilities are found
      ignore-unfixed: true
      vuln-type: 'os,library'
      severity: 'CRITICAL,HIGH'
```
