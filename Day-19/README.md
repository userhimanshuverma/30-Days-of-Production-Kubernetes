# 🔧 Day 19: Debugging Kubernetes Like a Production Engineer
### 🏷️ PHASE 3 — OBSERVABILITY & PRODUCTION OPERATIONS

Welcome to Day 19 of the **30 Days of Production Kubernetes** course. Today, we step into the shoes of a Senior Site Reliability Engineer (SRE). 

In a production cluster processing millions of requests, failures are a matter of *when*, not *if*. SREs do not debug by clicking randomly or guessing fixes; they employ a structured, evidence-based debugging workflow to reduce MTTR (Mean Time to Resolution) while protecting client SLAs. Today, you will master the diagnostics mindset and tools needed to resolve the most common Kubernetes production failures.

---

## 🗺️ Day 19 Directory Structure

Here is how today's learning resources are organized:
-   [notes/core-concepts.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/notes/core-concepts.md) — Advanced reference guide covering kernel-level mechanisms (cgroups, OOM score, exit codes), network packet routing (iptables, IPVS, kube-proxy), and DNS resolution details.
-   [diagrams/README.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/diagrams/README.md) — 12 professional diagrams outlining triage loops, DNS resolution steps, network paths, and SRE incident response workflows.
-   [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-19/manifests/) — Production-ready test files simulating failures:
    *   [crashloop-db-missing.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-19/manifests/crashloop-db-missing.yaml) — Simulates database credentials startup crash.
    *   [oomkilled-mem-leak.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-19/manifests/oomkilled-mem-leak.yaml) — Simulates a fast memory leak pod hitting limits.
    *   [service-selector-broken.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-19/manifests/service-selector-broken.yaml) — Simulates a broken service with selector mismatch.
    *   [dns-resolution-broken.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-19/manifests/dns-resolution-broken.yaml) — Simulates a pod with overridden nameserver settings.
    *   [debugging-toolkit.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-19/manifests/debugging-toolkit.yaml) — Swiss Army knife troubleshooting pod (netshoot) with capabilities to capture packets.
-   [labs/](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/) — 10 step-by-step engineering labs:
    *   [Lab 1: Diagnose CrashLoopBackOff](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-1-diagnose-crashloopbackoff.md)
    *   [Lab 2: Investigate OOMKilled Pods](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-2-investigate-oomkilled.md)
    *   [Lab 3: Debug Service Connectivity](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-3-debug-service-connectivity.md)
    *   [Lab 4: Resolve DNS Failures](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-4-resolve-dns-failures.md)
    *   [Lab 5: Analyze Kubernetes Events](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-5-analyze-kubernetes-events.md)
    *   [Lab 6: Use kubectl describe Effectively](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-6-use-kubectl-describe-effectively.md)
    *   [Lab 7: Debug Network Paths & Ephemeral Containers](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-7-debug-network-paths.md)
    *   [Lab 8: Investigate Production Incidents](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-8-investigate-production-incidents.md)
    *   [Lab 9: Build Troubleshooting Runbooks](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-9-build-troubleshooting-runbooks.md)
    *   [Lab 10: Conduct Root Cause Analysis](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-10-conduct-root-cause-analysis.md)
-   [incident-scenarios/](file:///d:/30_Days_of_Production_Kubernetes/Day-19/incident-scenarios/) — Real-world outage post-mortems:
    *   [Scenario 1: Database Outage](file:///d:/30_Days_of_Production_Kubernetes/Day-19/incident-scenarios/scenario-1-database-outage.md) — Connection pool leaks causing global 5xx errors.
    *   [Scenario 2: DNS Outage](file:///d:/30_Days_of_Production_Kubernetes/Day-19/incident-scenarios/scenario-2-dns-outage.md) — Upstream lookup latencies triggering CoreDNS timeouts.
    *   [Scenario 3: Resource Exhaustion](file:///d:/30_Days_of_Production_Kubernetes/Day-19/incident-scenarios/scenario-3-resource-exhaustion.md) — Node disk pressure causing catastrophic cascading pod evictions.
    *   [Scenario 4: Application Crash](file:///d:/30_Days_of_Production_Kubernetes/Day-19/incident-scenarios/scenario-4-application-crash.md) — Out-of-sync GitOps config schema crashing workloads.
-   [production-notes/senior-sre-ops.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/production-notes/senior-sre-ops.md) — Operational guidelines for on-call structures, war room rules, blameless RCAs, and MTTR reduction.
-   [troubleshooting/runbooks.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/troubleshooting/runbooks.md) — 10 immediate playbooks for common pod and network status errors.
-   [exercises/assignment.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/exercises/assignment.md) — Main daily coding/troubleshooting challenge: repair a degraded multi-tier microservice.
-   [incident-command-center.html](file:///d:/30_Days_of_Production_Kubernetes/Day-19/incident-command-center.html) — Futuristic, interactive single-page HTML simulator. Trigger outages (OOM, DNS, selectors, crashes), execute mock kubectl commands, monitor logs, apply hotfixes, and submit RCAs.

---

## 1. The SRE Debugging Mindset: Symptoms vs. Root Causes

Production engineers distinguish clearly between the **symptoms** of a failure and its **root cause**:
*   **Symptom:** A web application displays `502 Bad Gateway` (what the user/monitoring sees).
*   **Intermediate Cause:** The container is trapped in `CrashLoopBackOff` (what Kubernetes sees).
*   **Root Cause:** A missing database configuration key in the ConfigMap (the fundamental system state error).

### The Evidence-Based Debugging Workflow

```
Alert Fired ➔ Inspect Pod Status ➔ Collect Container Logs & Events ➔ Formulate Hypothesis ➔ Validate / Mitigate
```

SREs follow a structured triage checklist:
1.  **Isolate:** Determine if the issue is global (e.g. DNS, CNI network policy) or local to a single pod/node.
2.  **Verify Pod Phases:** Use `kubectl get pods` to verify if the pod is `Pending`, `Running`, or `Failed`.
3.  **Audit Events:** Use `kubectl get events --field-selector type=Warning` to view recent API server complaints.
4.  **Examine Container logs:** Check `kubectl logs <pod> --previous` to audit exit codes of crashed processes.

---

## 2. CrashLoopBackOff Deep Dive: Why Containers Crash

A `CrashLoopBackOff` state indicates that the container boots up, executes, but crashes immediately, forcing Kubernetes to delay restarts using an exponential backoff loop.

Common categories:
1.  **Startup configuration failures:** Missing critical env keys or credentials.
2.  **Dependency unavailability:** DB host name not resolving, or port unreachable.
3.  **Incorrect command/arguments:** The container's `Entrypoint` binary cannot be found or has invalid permissions.

*Read more in the [CrashLoopBackOff Runbook](file:///d:/30_Days_of_Production_Kubernetes/Day-19/troubleshooting/runbooks.md#1-crashloopbackoff-startup-failure) and practice hands-on in [Lab 1](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-1-diagnose-crashloopbackoff.md).*

---

## 3. OOMKilled Analysis: The Cgroup Boundary

When a container consumes memory beyond its limits, the Linux kernel terminates the process using `SIGKILL` (Exit Code 137). Kubernetes reports this state as `OOMKilled`.

Key concepts:
*   **cgroups (Control Groups):** The Linux kernel subsystem enforcing memory limit boundaries.
*   **oom_score_adj:** How Kubernetes adjusts the kernel's likelihood to kill processes based on Quality of Service (QoS) classes: Guaranteed, Burstable, and BestEffort.

*Review the [OOMKilled Analysis Guide](file:///d:/30_Days_of_Production_Kubernetes/Day-19/notes/core-concepts.md#2-memory-limits--oomkilled-exit-code-137) and complete [Lab 2](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-2-investigate-oomkilled.md).*

---

## 4. Network Troubleshooting & Service Connectivity

Kubernetes pods load balance connections to other pods through `Services` configured via `kube-proxy` rules (iptables or IPVS mode).

Common bottlenecks:
*   **Empty Endpoints:** Mismatched labels in Service selectors cause the Service to route queries to an empty endpoints list.
*   **Port Alignments:** `targetPort` configured in Service fails to match the actual application `containerPort`.

*Inspect the [Network Triage Flowchart](file:///d:/30_Days_of_Production_Kubernetes/Day-19/diagrams/README.md#4-network-troubleshooting-process) and complete [Lab 3](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-3-debug-service-connectivity.md).*

---

## 5. DNS Debugging: The ndots Trap

In Kubernetes, Pod DNS resolutions rely on `CoreDNS` configuration parameters injected into `/etc/resolv.conf`.

*   **ndots:5 default:** Causes the resolver to append search paths (e.g. `.default.svc.cluster.local`) to external URLs (e.g. `api.stripe.com`) first, generating multiple failing DNS requests before attempting the direct path lookup. This amplifies queries hitting CoreDNS, causing packet drops under load.

*Review the [DNS Concept Guide](file:///d:/30_Days_of_Production_Kubernetes/Day-19/notes/core-concepts.md#4-dns-resolution--service-discovery-resolvconf--ndots) and complete [Lab 4](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/lab-4-resolve-dns-failures.md).*

---

## 🏁 Summary of Daily Tasks

To complete Day 19:
1.  **Open the Interactive Simulator:** Launch [incident-command-center.html](file:///d:/30_Days_of_Production_Kubernetes/Day-19/incident-command-center.html) in your browser. Trigger and diagnose each of the four incidents, execute kubectl terminal instructions, mitigate the failures, and submit your RCA report.
2.  **Study Deep-Dive Notes:** Review [notes/core-concepts.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/notes/core-concepts.md) to master exit codes, cgroup configurations, Netfilter iptables, and DNS queries.
3.  **Review the Diagrams:** Examine [diagrams/README.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/diagrams/README.md) to inspect SRE triage paths and network boundaries.
4.  **Execute the Labs:** Complete [Labs 1 to 10](file:///d:/30_Days_of_Production_Kubernetes/Day-19/labs/) inside your cluster environment using the configs in [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-19/manifests/).
5.  **Review Production Operations:** Study [production-notes/senior-sre-ops.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/production-notes/senior-sre-ops.md) and [troubleshooting/runbooks.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/troubleshooting/runbooks.md).
6.  **Complete the Challenge:** Implement all fixes to stabilize the degraded workload inside [exercises/assignment.md](file:///d:/30_Days_of_Production_Kubernetes/Day-19/exercises/assignment.md).
