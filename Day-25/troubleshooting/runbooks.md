# 🚨 SRE Runbook: Multi-Cluster Troubleshooting Playbook

This playbook provides step-by-step diagnostic workflows and recovery procedures for five common multi-cluster production failure scenarios.

---

## 🛑 Scenario 1: Cross-Cluster Packet Drops (Cilium Mesh CA Mismatch)

### Symptoms
*   Pods inside `kind-east` can talk to local pods, but any attempt to connect to pods in `kind-west` fails with `Connection Timeout`.
*   Direct IP ping between clusters fails.

### Root Cause
When establishing Cilium ClusterMesh, both clusters must trust a shared **Certificate Authority (CA)**. If you run `cilium install` on both clusters without explicitly syncing certificates, each cluster generates a unique, self-signed CA. When the eBPF tunnel tries to authenticate cross-cluster traffic, the handshake fails due to untrusted certificates.

### Investigation & Diagnostics
1.  **Check ClusterMesh Status**:
    ```bash
    cilium clustermesh status --context east
    ```
    Look for error messages:
    ```
    ❌ ClusterMesh tunnel status: Handshake failed (Unknown CA / Bad Certificate)
    ```

2.  **Inspect Cilium DaemonSet logs**:
    ```bash
    kubectl logs -n kube-system -l k8s-app=cilium --context east --tail=100 | grep -i "handshake"
    # Output shows TLS certificate verification failures
    ```

### Resolution & Workaround
Extract the CA certificates from the primary cluster and inject them into the secondary cluster before enabling the mesh:

1.  **Export CA from `east`**:
    ```bash
    kubectl get secret -n kube-system cilium-ca -o yaml --context east > cilium-ca.yaml
    ```
2.  **Replace CA in `west`**:
    ```bash
    # Delete the local CA in west
    kubectl delete secret -n kube-system cilium-ca --context west
    # Apply the east CA to west
    kubectl apply -f cilium-ca.yaml --context west
    ```
3.  **Restart Cilium pods to reload certificates**:
    ```bash
    kubectl rollout restart ds/cilium -n kube-system --context west
    ```

### Prevention
*   Utilize **cert-manager** linked to a central HashiCorp Vault cluster to automatically issue and rotate certificates across the entire fleet.

---

## 🛑 Scenario 2: Federation Sync Loop Lockup (Karmada Webhook Hang)

### Symptoms
*   Updates applied to the Karmada Hub do not propagate to member clusters.
*   Resources applied in the Karmada API Server are stuck in `Terminating` or `Updating` status.

### Root Cause
Karmada uses **Mutating and Validating Admission Webhooks** to inject override properties and evaluate propagation rules. If the webhook pod (e.g. `karmada-webhook`) crashes or runs out of resources, the API server blocks all resource modifications, waiting for a response that never arrives.

### Investigation & Diagnostics
1.  **Check Webhook Pod Health**:
    ```bash
    kubectl get pods -n karmada-system -l app=karmada-webhook --kubeconfig ~/.kube/karmada.config
    ```
2.  **Inspect API Server Block Logs**:
    ```bash
    kubectl describe deployment dynamic-web-frontend -n production --kubeconfig ~/.kube/karmada.config
    ```
    Look for webhook connection timeouts in the events list:
    ```
    Internal error occurred: failed calling webhook "mutation.karmada.io": failed to call webhook: Post "https://karmada-webhook.karmada-system.svc:443/mutate...": context deadline exceeded
    ```

### Resolution & Workaround
If the webhook is blocking critical updates, you can temporarily disable it to restore control:

1.  **List Webhook Configurations**:
    ```bash
    kubectl get mutatingwebhookconfigurations --kubeconfig ~/.kube/karmada.config
    ```
2.  **Edit/Delete the Blocked Webhook**:
    ```bash
    kubectl delete mutatingwebhookconfiguration karmada-webhook --kubeconfig ~/.kube/karmada.config
    ```
    *Note*: Disabling webhooks will allow you to modify resources, but propagation rules may apply without overrides until the webhook service is restored and re-applied.

### Prevention
*   Ensure webhook configurations define a strict `timeoutSeconds` (e.g., `3s`) and configure `failurePolicy: Ignore` for non-critical hooks to prevent API lockups during outages.

---

## 🛑 Scenario 3: Stale DNS Cache (GeoDNS Failover Black Hole)

### Symptoms
*   `us-east-1` cluster is completely offline.
*   The GSLB has updated DNS records to point to `eu-west-1`.
*   However, up to 25% of users in the US still get connection timeouts or `502 Bad Gateway` pages.

### Root Cause
Clients or their ISP DNS resolvers are caching the stale IP address of the offline `us-east-1` ingress point, ignoring the DNS Time-to-Live (TTL) configuration.

### Investigation & Diagnostics
1.  **Perform DNS Query against Local GSLB**:
    ```bash
    dig api.global.company.com
    # Verify GSLB returns the healthy European IP (198.51.100.20)
    ```
2.  **Query DNS using Google Public DNS (8.8.8.8) or Cloudflare (1.1.1.1)**:
    ```bash
    dig @8.8.8.8 api.global.company.com
    # If this returns the offline US IP (192.0.2.10), intermediate DNS resolvers are caching the record.
    ```

### Resolution & Workaround
*   **DNS Flush**: Instruct users to flush their DNS cache, or trigger a zone flush via your DNS provider's API (e.g., Cloudflare API).
*   **Anycast Migration**: Route traffic through an Anycast CDN edge proxy (like Cloudflare or AWS CloudFront) rather than using GeoDNS directly at the origin load balancer. The CDN will instantly redirect requests to healthy backend regions without relying on client-side DNS updates.

### Prevention
*   Set DNS TTLs to short intervals (**10 to 30 seconds**).
*   Avoid routing clients directly to origin load balancer IPs. Shield endpoints behind an edge proxy that handles health checking and failover routing internally.

---

## 🛑 Scenario 4: Multi-Cluster GitOps Drift

### Symptoms
*   An application's configuration behaves differently across clusters.
*   ArgoCD shows the application as `Synced`, but local configurations differ.
*   Manual edits to the cluster are repeatedly overwritten, triggering sync loops.

### Root Cause
Operators are bypassing the GitOps repository and running manual modifications (`kubectl edit` or `kubectl apply`) directly on member clusters. This causes drift that the central GitOps engine may fail to reconcile if the resource is excluded from monitoring or if auto-healing is disabled.

### Investigation & Diagnostics
1.  **Check Sync Diff in ArgoCD**:
    ```bash
    argocd app diff application-name
    ```
    This highlights any differences between target Git configuration and actual cluster state.
2.  **Identify the Source of Manual Changes**:
    Check the resource's metadata for manual annotation modifications:
    ```bash
    kubectl get deployment dynamic-web-frontend -n production -o yaml --context east
    # Look for manual annotations or resource limits that do not match the Git repository
    ```

### Resolution & Workaround
1.  **Enable Self-Healing & Auto-Pruning in ArgoCD**:
    Configure the application sync policy in Git:
    ```yaml
    syncPolicy:
      automated:
        prune: true
        selfHeal: true
    ```
2.  **Manually Trigger Reconciliation**:
    ```bash
    argocd app sync application-name --force
    ```
    This forces ArgoCD to overwrite any manual changes and align the cluster state with Git.

### Prevention
*   Enforce strict RBAC policies. Revoke direct write permissions (`create`, `update`, `delete`, `patch`) for human operators on production clusters. All configuration changes must proceed through Git pull requests.

---

## 🛑 Scenario 5: Split-Brain Database Synchronization Failures

### Symptoms
*   Both regional database clusters report their status as `Primary / Write Node`.
*   Data written to `US-East` does not sync to `EU-West`.
*   When the network connection is restored, database replication fails due to divergent transactional sequences (diverging logs).

### Root Cause
During a network partition, both regions lost connection to each other. If the system was misconfigured to automate failovers without checking for quorum, both regions may have assumed the other was dead and promoted their local database node to primary, resulting in **split-brain**.

### Investigation & Diagnostics
1.  **Inspect Database Master Logs**:
    Search for replication sync errors:
    ```
    ❌ ERROR: divergent write sequences detected. Cannot merge WAL history logs.
    ```
2.  **Compare Transactional IDs (LSN - Log Sequence Number)**:
    Compare the current LSN of both databases. If both have advanced independently, the data has diverged, and simple replication cannot resume.

### Resolution & Workaround
Recovering from a split-brain divergence requires manual reconciliation:

1.  **Halt Writes**:
    Instantly set the database in one region (usually the secondary or lower-priority region) to **Read-Only** mode to prevent further data drift.
2.  **Backup Both Databases**:
    ```bash
    pg_dumpall -h db-us.internal.company.com > db-us-backup.sql
    pg_dumpall -h db-eu.internal.company.com > db-eu-backup.sql
    ```
3.  **Restore and Rebuild Replication**:
    Point the secondary database region back to the primary database, restoring it from a backup if necessary. This will overwrite conflicting local changes in the secondary region.
4.  **Manually Merge Divergent Transactions**:
    Write scripts to compare the backup file of the overwritten region and manually insert any missing records (e.g. lost user updates) back into the primary database.

### Prevention
*   Always use an odd number of voting nodes (e.g., 3 regions or a 3-node controller layout) to ensure database consensus. A network partition will prevent the isolated region from reaching quorum, allowing it to automatically disable writes and prevent split-brain drift.
