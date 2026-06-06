# 🧪 Lab 3: Secret Protection, etcd Encryption & External Vaults

This lab explains why standard Kubernetes Secrets are insecure by default, how to enable control plane encryption at rest, and how to integrate external secret managers (like HashiCorp Vault or AWS Secrets Manager).

---

## Step 1: Demystifying Base64 vs. Encryption

By default, Kubernetes Secrets are stored in `etcd` as plain text (encoded only in Base64). Let's prove why this is not secure.

1. Create a dummy secret containing database credentials:
   ```bash
   kubectl create secret generic db-creds \
     --from-literal=username=admin \
     --from-literal=password=SuperSecretPassword123! \
     -n default
   ```
2. Retrieve the raw manifest details:
   ```bash
   kubectl get secret db-creds -o yaml
   ```
3. Decode the password using a standard base64 tool:
   ```bash
   # Extract and decode the password field
   kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 --decode
   ```
   *Output: `SuperSecretPassword123!`*

Anyone with read permissions on secrets, or access to etcd backups, can retrieve this password instantly. Base64 is merely a serialization format, **not** encryption.

---

## Step 2: Configuring Encryption at Rest (API Server)

To encrypt secrets before writing them to the etcd key-value database, the API Server must be configured with an encryption config file.

1. Review the structure in [manifests/secret-encryption-config.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/secret-encryption-config.yaml).
2. To enable this on a control plane node (e.g. standard kubeadm/kind setup):
   - Copy the configuration file to `/etc/kubernetes/pki/encryption-config.yaml` on the master node.
   - Edit `/etc/kubernetes/manifests/kube-apiserver.yaml` to pass the config flag to the API Server arguments:
     ```yaml
     spec:
       containers:
         - name: kube-apiserver
           command:
             - kube-apiserver
             # Add this line:
             - --encryption-provider-config=/etc/kubernetes/pki/encryption-config.yaml
     ```
   - Add the host mount volumes so the API Server container can access the configuration file:
     ```yaml
     # Inside volumeMounts:
     - mountPath: /etc/kubernetes/pki/encryption-config.yaml
       name: encryption-config
       readOnly: true
     # Inside volumes:
     - hostPath:
         path: /etc/kubernetes/pki/encryption-config.yaml
         type: File
       name: encryption-config
     ```
3. When the API Server restarts, all **new** secrets will be stored as encrypted ciphertext in etcd.
4. To encrypt existing secrets in the cluster, run:
   ```bash
   # Reading and writing all secrets triggers the API server to encrypt them
   kubectl get secrets --all-namespaces -o json | kubectl replace -f -
   ```

---

## Step 3: Integrating External Vaults (External Secrets Operator)

In large-scale production setups, you do not write Secret YAML files at all. Instead, secrets are stored in a centralized Vault, and synchronized to the cluster dynamically.

1. Review the manifest [manifests/external-secret-example.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-15/manifests/external-secret-example.yaml).
2. **The Components:**
   - **`SecretStore`**: Defines the connection details to the external system (e.g. Vault endpoint URL). It specifies how the operator authenticates. Here, we use **Kubernetes service account token projection** to authenticate. Vault verifies the SA token against the API server to confirm the Pod's identity.
   - **`ExternalSecret`**: Maps a specific key in the external vault (e.g. `production/database` username and password fields) to a resulting Kubernetes Secret named `db-secret-k8s`.
3. In a real environment, once the External Secrets Operator is installed:
   ```bash
   # Add the helm repository
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
   
   # Apply the secret configurations
   kubectl apply -f manifests/external-secret-example.yaml
   ```
4. Check if the synchronized secret was created automatically:
   ```bash
   kubectl get secret db-secret-k8s -n production
   ```
   The database credentials are now safely synchronized into memory and available for Pod volume mounts.
