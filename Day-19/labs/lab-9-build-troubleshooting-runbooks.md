# 🧪 Lab 9: Build Troubleshooting Runbooks

## Objective
Learn how to design and structure actionable, high-quality SRE runbooks for on-call engineering teams to minimize MTTR.

---

## What Makes a Runbook "Actionable"?

A bad runbook contains vague descriptions like: *"If the system is slow, restart it."*  
A premium SRE runbook provides:
1.  **Alert Correlation:** Exact alert names that map to this runbook.
2.  **Triage Steps:** CLI commands with expected outputs to verify the state.
3.  **Mitigation Rules:** Simple scripts or copy-paste commands to restore service immediately.
4.  **Escalation Details:** Who to contact if the mitigation fails.

---

## Lab Challenge: Build a Runbook Template

Create a runbook for your on-call team to handle **Redis Connection Timeouts**.

### Step 1: Draft the Runbook Structure
Create a markdown document `redis-timeouts-runbook.md` with these four sections:

```markdown
# Runbook: Redis Connection Timeouts

## 1. Alert Indicators
*   `RedisClientConnectionFailuresAlert`
*   `checkout-api-redis-latency-spike`

## 2. Immediate Diagnostic Checks
Run this command to check if Redis is responding:
```bash
kubectl exec -it statefulset/redis-leader-0 -- redis-cli ping
```
*Expected Output:* `PONG`  
*If no response or connection timeout:* Redis is hung or offline.

## 3. Mitigation Steps
If Redis is unresponsive, trigger a failover by deleting the master pod (StatefulSet will automatically restart it, and sentinel will promote a replica):
```bash
kubectl delete pod redis-leader-0 --grace-period=0
```
Monitor the sentinel failover logs:
```bash
kubectl logs -l app=redis-sentinel --tail=50
```

## 4. Escalation Path
If the failover fails or data corruption is detected, page the **Data Platform On-Call Team** via PagerDuty or channel `#data-platform-ops`.
```

### Step 2: Validate Runbooks inside Git
A runbook should be stored alongside the service code or in a centralized `ops-runbooks` repository. During CI, run markdown linting checks to ensure code block formatting is correct and all paths are valid.
