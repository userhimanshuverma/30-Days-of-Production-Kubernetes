# 🏆 Day 7 Exercises & Challenges

Test your understanding of Kubernetes configuration and secrets management by completing these three progressive configuration challenges.

---

## Challenge 1: The Hardened Config Map & Volume Mount

### Objective
Deploy a configuration file to a container safely using directory-based volume mounts, ensuring the file is strictly read-only for the application container.

### Requirements
1. Create a ConfigMap named `app-settings` containing:
   * A key named `config.json` containing:
     ```json
     {
       "database": {
         "host": "postgres-prod.internal",
         "port": 5432
       },
       "features": {
         "beta_ui": true,
         "cache_enabled": false
       }
     }
     ```
2. Deploy a single-replica Pod named `config-tester` that:
   * Mounts the ConfigMap under `/etc/app/config/`.
   * Enforces strict read-only permissions on the volume mount.
   * Ensures the file permission is set to `0400` (readable only by the owner).
   * Runs as a non-root user (UID `10001`).

### Solution Outline
* **Hint:** Look at the `defaultMode` property inside the Pod volumes specification. Remember to set `securityContext` on the Pod or Container level to run as UID `10001`.

---

## Challenge 2: Environment Variable Safe Extraction

### Objective
Create a secure database worker Pod that extracts database credentials from a Kubernetes Secret and environment values from a ConfigMap.

### Requirements
1. Create an Opaque Secret named `db-credentials` containing base64 values for:
   * `DB_USER`
   * `DB_PASSWORD`
2. Create a ConfigMap named `db-network` containing:
   * `DB_HOST`
   * `DB_PORT`
3. Create a deployment named `db-client-worker` that:
   * Uses `env` to map `DB_USER` and `DB_PASSWORD` from the Secret resource.
   * Uses `envFrom` to map all values from the ConfigMap as environment variables directly.
4. Verify using `kubectl exec` that the environment variables are correctly injected and resolve to the correct values.

---

## Challenge 3: Simulate Secret Rotation

### Objective
Implement a local loop to observe how Kubelet rotates secrets on node disks.

### Steps
1. Create a Secret:
   ```bash
   kubectl create secret generic rotation-demo --from-literal=api-key=v1-alpha-token
   ```
2. Deploy a Pod `rotation-watcher` that mounts this Secret as a volume at `/var/secrets`.
3. In a terminal window, run a watch command to monitor the secret file contents:
   ```bash
   kubectl exec -it rotation-watcher -- watch -n 1 cat /var/secrets/api-key
   ```
4. In another terminal window, update the secret to use `v1-beta-token`:
   ```bash
   kubectl create secret generic rotation-demo --from-literal=api-key=v1-beta-token --dry-run=client -o yaml | kubectl apply -f -
   ```
5. Observe the watch window. Note the duration of time it takes before the file updates.
6. Write a short explanation answering: *Why did the secret update on disk without restarting the pod? What happens to the symlink directory structure inside `/var/secrets` during the update?*
