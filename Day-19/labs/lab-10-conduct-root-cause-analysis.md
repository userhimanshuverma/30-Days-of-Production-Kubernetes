# 🧪 Lab 10: Conduct Root Cause Analysis (RCA)

## Objective
Learn how to host a blameless post-mortem and write a comprehensive Root Cause Analysis (RCA) document after a major production outage.

---

## The RCA Methodology: Blameless & Systemic

A blameless post-mortem assumes that engineers act in good faith with the information they have. Rather than blaming a developer for "writing a bad query," SREs ask: *Why was the developer able to deploy a bad query to production without triggering a safeguard?*

---

## Lab Challenge: Draft a Post-Mortem

Use the following template to write a post-mortem for the **Database connection leak outage** described in [scenario-1-database-outage.md](../incident-scenarios/scenario-1-database-outage.md).

### Step 1: Draft the Metadata Block
Create a markdown file containing the critical incident metrics:

```markdown
# Incident Post-Mortem: Checkout API Database Connection Saturation

| Incident Owner | On-Call SRE | Severity | Date |
| :--- | :--- | :--- | :--- |
| SRE Team | Sunny | Sev0 | 2026-06-10 |

**Total Outage Duration:** 42 Minutes  
**MTTR (Mean Time to Resolution):** 42 Minutes  
**SLA Impact:** 99.8% checkout success rate target dropped to 0% during the incident.
```

### Step 2: Write the Incident Summary
Write a brief, high-level summary of what happened:
```text
Between 14:02 and 14:44 UTC, our Checkout API service experienced a 100% failure rate due to database connection exhaustion. The database reached its maximum configuration limit of 500 active sessions, refusing connection attempts from newly spawned pods. The outage was mitigated by rolling back checkout-api from v2.3.1 to v2.3.0 and clearing idle database connection processes.
```

### Step 3: Map the Incident Timeline
Detail the timeline of events, observations, and mitigations:
*   `14:02` - Alert triggers for HTTP 5xx errors on checkout-api.
*   `14:05` - On-Call SRE starts triage; validates pods are running.
*   `14:10` - Application logs show connection pool exhaustion.
*   `14:18` - Postgres logs show "FATAL: remaining connection slots are reserved...".
*   `14:28` - Rollback to v2.3.0 executed.
*   `14:32` - Active idle sessions terminated manually on Postgres.
*   `14:35` - Connection pool levels normalize; errors drop to zero.

### Step 4: Perform the "5 Whys" analysis
1.  *Why did checkouts fail?* Postgres connections were exhausted.
2.  *Why?* Checkout API pods kept connections open indefinitely.
3.  *Why?* The transaction code in v2.3.1 failed to call `rows.Close()`.
4.  *Why?* There was no automated code validation or unit test catching connection leaks.
5.  *Why?* Our CI linting pipelines do not enforce static analysis rules for database queries.

### Step 5: Assign Action Items
Create tracking items with owners and deadlines:
*   [ ] Deploy pgBouncer database proxy to pool connections (Owner: DB-Ops, Priority: P0).
*   [ ] Add `sqlclosecheck` static code analyzer to github workflows (Owner: CI-CD Devs, Priority: P1).
*   [ ] Create automated alert for Postgres connections > 85% capacity (Owner: Observability-Team, Priority: P1).
