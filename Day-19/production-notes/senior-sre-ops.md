# 🚨 Senior SRE Production Operations & Incident Management

Operating large-scale Kubernetes clusters in production requires more than technical knowledge of `kubectl` commands. It requires structured incident management protocols, clear escalation paths, and a culture of continuous learning through Root Cause Analysis (RCA).

This document outlines the operational patterns used by elite SRE teams to reduce MTTR (Mean Time To Resolution) and maintain high availability.

---

## 1. The Incident Command System (ICS) for SRE

During a high-severity (Sev1/Sev0) outage, chaos is the enemy. SRE teams use a simplified version of the Incident Command System to assign clear operational roles:

*   **Incident Commander (IC):** 
    *   *Role:* Leads the incident response. Does not write code or run commands.
    *   *Responsibility:* Coordinates the team, assigns tasks, manages communications, and makes final decisions on mitigations (e.g., approving a rollback).
*   **Communications Lead (Comm Lead):** 
    *   *Role:* Handles updates to stakeholders, support teams, and public status pages.
    *   *Responsibility:* Keeps stakeholders informed so the technical team can focus on debugging without interruption.
*   **Ops Lead (Primary Investigator):** 
    *   *Role:* The SRE/Engineer executing diagnostics.
    *   *Responsibility:* Inspects metrics, checks logs, runs commands, and reports findings back to the IC.

> [!TIP]
> **War Room Practice:** When an incident starts, immediately establish a dedicated bridge (Google Meet/Slack channel). All chatter should go through the channel. The IC should compile a timeline of actions and observations in real-time.

---

## 2. Reducing MTTR: Mitigation vs. Investigation

A common anti-pattern for junior engineers is attempting to find the *root cause* while the site is still down. 

### The SRE Priority Loop
```
Triage ➔ Mitigate (Restore SLA) ➔ Investigate Root Cause (Post-Outage) ➔ Prevent
```

*   **Mitigation First:** If a recent deployment caused an outage, **rollback immediately**. Do not spend 45 minutes analyzing stack traces while users experience 500 errors. 
*   **Scale Up:** If memory pressure is causing OOMKilled states, increase resources or scale replicas immediately to stabilize the cluster.
*   **Isolate Traffic:** Route requests away from the degraded zone/namespace if possible.

Only when the system metrics return to baseline (SLA is restored) should the team pivot to deep forensics and root-cause discovery.

---

## 3. Production Debugging Anti-Patterns

Avoid these common pitfalls when diagnosing active incidents:

### 1. "Restart and Hope" (SIGKILL-driven engineering)
Restarting pods clears symptoms (e.g., freeing leaked memory or restoring connections), but without collecting diagnostics, you destroy the evidence.
*   *Correction:* Always run `kubectl logs <pod> --previous` or dump container state memory before killing a misbehaving pod.

### 2. Tail-Chasing on Single Metric Spikes
Focusing exclusively on a single host's high CPU usage when the root cause is actually database lock contention.
*   *Correction:* Look at system-wide metrics (ingress latencies, database connections) before deep-diving into individual pod specs.

### 3. Modifying Manifests Directly in Production
Using `kubectl edit` during an incident without tracking changes in Git. This leads to configuration drift, causing subsequent GitOps reconciliations to overwrite your hotfixes.
*   *Correction:* Use your CI/CD bypass flags if necessary, but ensure all hotfixes are merged back to Git immediately.

---

## 4. Post-Mortem and Root Cause Analysis (RCA) Guidelines

Every major incident must end with a post-mortem. A good post-mortem focuses on processes and systems, not human error (Blameless Post-Mortem).

### The "5 Whys" Technique
Used to drill down past symptoms to find the systemic flaw:
*   *Problem:* payment-service went down due to OOMKilled.
    1.  *Why?* The container exceeded its 256Mi memory limit.
    2.  *Why?* A recent code change loaded an entire database table into memory.
    3.  *Why?* The database query was missing pagination parameters.
    4.  *Why?* The code reviewer missed the missing pagination logic.
    5.  *Why?* We do not have a static code analysis check or automated test to flag non-paginated queries. (Systemic Root Cause!)

### Action Item Categories
Preventive actions must be concrete:
*   **Mitigation:** Add automatic pagination checks to code linter.
*   **Detection:** Add Prometheus alerts for rapid memory growth rate.
*   **Escalation:** Update page alerts to route to the database team if query queue times exceed 1s.

---

*Proceed to the [troubleshooting/](../troubleshooting/) folder to access production runbooks for CrashLoopBackOff, OOMKilled, and connectivity failures.*
