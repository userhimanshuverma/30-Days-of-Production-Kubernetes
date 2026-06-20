# Encrypting GitOps Secrets: Mozilla SOPS & PGP Integration

This guide details how to securely encrypt Kubernetes Secrets using Mozilla SOPS and PGP keys before committing manifests to public or private Git repositories.

---

## 🚫 The GitOps Secrets Problem
In a GitOps pipeline, everything inside Git is pushed directly into the cluster. However, standard Kubernetes Secret resources are stored as plain **Base64 encoded strings** (NOT encrypted). Committing standard Secrets directly to Git is a critical security vulnerability.

---

## 🛠️ Mozilla SOPS (Secrets Operations)
SOPS allows you to encrypt only the `value` fields inside a Kubernetes Secret YAML manifest, leaving the metadata (api version, name, kind, namespaces) in plain readable text. This allows ArgoCD/Flux to track and apply the manifest structure while keeping the credentials secure.

---

## 📋 Step-by-Step Encryption Guide

### Step 1: Install SOPS
*   **macOS**: `brew install sops`
*   **Ubuntu/Debian**: `sudo apt install sops` or download deb package from Github Releases.
*   **Windows**: Download installer or execute `choco install sops`.

### Step 2: Generate local PGP Key
Generate a PGP key pair on your local SRE machine:
```bash
gpg --generate-key
# Retrieve the GPG Key Fingerprint ID:
gpg --list-secret-keys --keyid-format LONG
```
*Locate the 40-character fingerprint code (e.g. `2F3D9A4C...`).*

### Step 3: Encrypt Kubernetes Secret
Create a standard unencrypted Secret manifest file (`secret-raw.yaml`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-database-secrets
  namespace: default
stringData:
  db-password: super-secret-password-123
```

Run SOPS to encrypt the values using your PGP key fingerprint:
```bash
sops --encrypt --pgp <YOUR-PGP-FINGERPRINT> secret-raw.yaml > secret-encrypted.yaml
```

Inspect `secret-encrypted.yaml`. You will notice `stringData` is encrypted into pgp strings, and sops config blocks are added, but `apiVersion` and `metadata.name` remain visible. This file is safe to commit to Git!

### Step 4: Decrypting at Deployment
To deploy manually, decrypt on the fly before piping to API Server:
```bash
sops --decrypt secret-encrypted.yaml | kubectl apply -f -
```
*In production, ArgoCD utilizes a SOPS plugin (e.g., Kustomize-sops) to decrypt variables dynamically inside cluster memory during sync loops.*
