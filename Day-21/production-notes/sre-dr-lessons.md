# ⚡ SRE Production Notes: Disaster Recovery & High Availability

These notes represent hard-won operational experience and engineering guidelines for managing mission-critical, high-availability Kubernetes platforms at scale.

---

## 1. The Fallacy of Untested Backups (Schrödinger's Backup)

> "The condition of any backup is unknown until you try to restore it."

In production, **taking backups is only 10% of the battle**. The other 90% is validating that those backups actually work when a recovery is needed.

### The Automated Validation Pipeline
To ensure backups are valid, set up a daily, automated validation pipeline:
1. **Trigger**: An automated scheduler (e.g., Jenkins, GitHub Actions, or a Kubernetes CronJob) triggers once a day.
2. **Retrieve**: It pulls the latest etcd snapshot and application backups (Velero) from production S3.
3. **Provision**: It spins up a temporary, isolated "sandbox" Kubernetes cluster (e.g., using Kind or ephemeral VM APIs).
4. **Restore**: It runs the etcd restore procedure and recovers application states.
5. **Assert**: It executes integration tests to verify the restored cluster's API works, pods boot, and database contents are readable.
6. **Destroy**: It tears down the sandbox cluster and logs a status check. If validation fails, it pages the on-call SRE.

---

## 2. Planning and Running "Game Days" (Chaos Engineering)

Disaster recovery plans fail during real outages because of human panic, outdated documentation, or forgotten credentials. SREs run **Game Days** to build muscle memory.

### Game Day Checklist:
* **The Black Box Test**: Simulate a complete region failure. Have an engineer cut network access to a zone without warning the on-call team, and measure the Recovery Time Objective (RTO).
* **Write Runbooks for Humans under Stress**: During a 3:00 AM outage, engineers cannot digest long paragraphs. Runbooks should be written in short, imperative commands:
  - *"Run command X. If output matches Y, proceed to step 2. If it matches Z, run command W."*
* **The "Bus Factor" Check**: Ensure that DR drills can be completed by junior engineers using only the runbook, without senior engineers whispering instructions.

---

## 3. Stateful Workload Recovery & Data Protection

While stateless apps are trivial to recover, stateful applications (e.g., PostgreSQL, Kafka) require special care.

### The Cloud-Storage Zone Trap
Cloud block storage (like AWS EBS or GCP Persistent Disks) is bound to a specific physical Availability Zone. 
* If `us-east-1a` fails, your PostgreSQL pod in `us-east-1b` **cannot mount** the EBS volume residing in `us-east-1a`.
* **SRE Strategy**: Use database-level replication (active-passive with streaming replicas or active-active via Raft/Paxos) rather than relying on volume-level backups. For critical DBs, host the primary in `us-east-1a` and a read-replica in `us-east-1b`. Use a failover controller (e.g., Patroni) to automatically promote the replica.

---

## 4. Cost vs. Availability Trade-offs

High availability is not free. SREs must align cluster design with business requirements (SLAs).

```
AVAILABILITY   RTO/RPO    ARCHITECTURAL PATTERN                COST MULTIPLIER
99.9%          Hours      Single Region, Multi-Zone, Cold DR   1.0x (Baseline)
99.99%         Minutes    Multi-Region, Warm Standby DR        2.5x
99.999%        Seconds    Multi-Region, Active-Active GSLB     4.0x+
```

### Key Considerations:
* **Cross-AZ Network Charges**: Cross-zone traffic accounts for up to 30% of a Kubernetes cluster's network bill. Enable topology-aware routing to keep intra-cluster microservice communications within the same zone.
* **Over-provisioning**: If you run in 3 zones and want to survive the loss of 1 zone without degraded performance, your surviving zones must have enough spare capacity. You must maintain at least 33% headroom across the remaining nodes.

---

## 5. Lessons Learned from Real Outages

### Case Study 1: The Cascading DNS Outage
* **Incident**: An SRE team simulated a control plane node failure. When the node went down, the cluster autoscaler spun up new nodes in a different zone.
* **The Gotcha**: The sudden influx of new pods caused a storm of DNS queries to CoreDNS. CoreDNS pods, which lacked CPU requests/limits, were throttled, leading to cluster-wide resolution failure.
* **Lesson**: When testing DR, look for secondary bottlenecks (DNS, IP exhaustion, Docker registry rate limits) that occur during rapid rescheduling.

### Case Study 2: The Stale Snapshot Restore
* **Incident**: A database corruption required restoring etcd from a 6-hour-old snapshot.
* **The Gotcha**: During the 6 hours since the snapshot, developers had merged new Helm releases. Once etcd was restored, Kubernetes deleted the physical pods and services that had been created in those 6 hours, leading to a silent deployment roll-back.
* **Lesson**: Run etcd backups frequently (at least hourly), and lock/freeze GitOps deployment pipelines (e.g., ArgoCD/Flux) during restore operations.
