# Production Kubernetes Mini-Projects

Challenge yourself with these hands-on mini-projects before tackling the main Day 30 Capstone Project.

---

## 🛠️ Mini-Project 1: Automated Namespace Tenant Provisioner
*   **Goal**: Build a system that automatically bootstraps a secure multi-tenant namespace with default guardrails whenever a developer requests one.
*   **Requirements**:
    1.  Create a bash script or custom operator that creates a Namespace.
    2.  Automatically deploy a default-deny `NetworkPolicy` to the new namespace.
    3.  Generate a local `ServiceAccount` and a `RoleBinding` restricting namespace modification access.
    4.  Configure `LimitRanges` restricting maximum container memory allocations to `1Gi`.

---

## 🛠️ Mini-Project 2: Self-Healing Postgres Replication Failover
*   **Goal**: Deploy a replicated database cluster and validate automated master election under node failure conditions.
*   **Requirements**:
    1.  Deploy a 3-replica PostgreSQL cluster using the CloudNativePG Operator.
    2.  Write a script to continuously write timestamp records to a table:
        ```sql
        INSERT INTO heartbeat (ts) VALUES (now());
        ```
    3.  Simulate a primary node failure by executing a hard eviction (`kubectl delete pod <postgres-primary> --grace-period=0 --force`).
    4.  Verify that secondary promotion completes in under 15 seconds, and confirm database writes continue without data corruption.

---

## 🛠️ Mini-Project 3: Elastic HTTP Scaling with KEDA
*   **Goal**: Configure advanced event-driven horizontal scaling using KEDA (Kubernetes Event-driven Autoscaling) instead of standard CPU-bound HPA.
*   **Requirements**:
    1.  Install the KEDA controller in your cluster.
    2.  Deploy a mock web server displaying metrics on `/metrics`.
    3.  Configure a KEDA `ScaledObject` that queries Prometheus metrics.
    4.  Trigger scaling rules based on HTTP request rates (RPS > 50) rather than CPU average thresholds, scaling replicas from 1 to 8.
