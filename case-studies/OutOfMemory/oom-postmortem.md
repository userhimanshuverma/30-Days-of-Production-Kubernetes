# SRE Incident Post-Mortem: JVM OutOfMemory (OOM) Crash Loop Storm

*   **Incident Reference**: INC-48902-checkout
*   **Severity**: P1 - Critical
*   **Date**: 2026-06-15
*   **Duration**: 42 minutes
*   **Services Impacted**: `checkout-service` in production cluster

---

## 📝 Executive Summary
On 2026-06-15 at 14:10 UTC, the `checkout-service` experienced a sudden latency spike followed by a complete service outage. All pod replicas restarted repeatedly, returning status `CrashLoopBackOff` with termination code `137`. The root cause was identified as a JVM heap configuration mismatch where Java calculated its maximum memory capacity based on the physical host VM memory (64 GiB) rather than the container cgroup limit (2 GiB). This caused the Linux kernel Out-Of-Memory (OOM) Killer to terminate the Java process. The service was restored by updating container JVM flags and right-sizing memory limits.

---

## ⏰ Incident Timeline (UTC)
*   **14:10** - PagerDuty alerts fire: `CheckoutServiceHttpErrorRateHigh` (Error rate > 5%).
*   **14:12** - SRE on-call joins war room. Pod status check shows all 10 replicas in `CrashLoopBackOff`.
*   **14:18** - Diagnostic check reveals exit code `137` on terminated containers.
*   **14:24** - SRE identifies JVM heap misconfiguration. Max Heap was expanding beyond cgroup limits.
*   **14:32** - Hotfix deployed updating deployment JVM environment parameters.
*   **14:38** - Pods complete rolling restart. Error rates return to baseline.
*   **14:52** - War room disbanded. Incident resolved.

---

## 🔍 Root Cause Analysis (RCA)

### Exit Code 137 & cgroup Limits
When a container is terminated with exit code `137`, it indicates the process received a `SIGKILL` signal. In Kubernetes, this most commonly occurs when the Linux kernel's Out-of-Memory (OOM) Killer terminates a container that exceeds its cgroup memory limit:

$$\text{Memory Consumption} > \text{cgroup Memory Limit}$$

### The JVM Container Gap
Java applications run inside a Virtual Machine (JVM). By default, older Java runtimes (pre-Java 10 or runtimes lacking container support flags) read memory sizing parameters directly from `/proc/meminfo`. 
*   **The Issue**: The host machine had **64 GiB** of RAM. The container had a memory limit of **2 GiB**.
*   **The Math**: Because explicit JVM memory arguments were not defined, the JVM calculated its default max heap size as $25\%$ of the system memory:
    $$\text{Default Max Heap} = 64\text{ GiB} \times 0.25 = 16\text{ GiB}$$
*   Since $16\text{ GiB}$ is significantly larger than the container's cgroup limit of $2\text{ GiB}$, the Java process expanded its heap under user transaction load until it hit the $2\text{ GiB}$ threshold. The host operating system kernel immediately issued a `SIGKILL` to prevent host exhaustion.

---

## 🛠️ Resolution & Hotfix
The deployment configuration was patched to make the JVM container-aware using explicit memory ratio parameters.

```yaml
# Before:
# No container configuration parameters defined in entrypoint.

# After (Hotfix applied to deployment):
env:
  - name: JAVA_TOOL_OPTIONS
    value: "-XX:+UseContainerSupport -XX:InitialRAMPercentage=70.0 -XX:MaxRAMPercentage=70.0"
resources:
  requests:
    memory: "2Gi"
    cpu: "500m"
  limits:
    memory: "2.5Gi" # Provided head room for JVM non-heap memory overhead
    cpu: "1000m"
```

---

## 📋 Action Items & Prevention
- [ ] **Standardize Java configurations**: Enforce the use of `-XX:+UseContainerSupport` and `-XX:MaxRAMPercentage` across all JVM-based templates.
- [ ] **Configure Memory Overhead buffer**: Always set container memory limits $20\%-30\%$ higher than JVM Max Heap to account for off-heap allocations (Metaspace, thread stacks, garbage collector structures).
- [ ] **Improve alerting**: Configure Alertmanager to trigger warnings when container memory consumption reaches $80\%$ of its limit.
