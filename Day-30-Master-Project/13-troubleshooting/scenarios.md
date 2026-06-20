# SRE Troubleshooting Playbook: 11 Platform Failure Scenarios

This document contains step-by-step diagnostic workflows and recovery procedures for eleven key production incident profiles.

---

## 🛠️ Incident 1: Pod Failures (CrashLoopBackOff)
*   **Symptoms**: Pods show status `CrashLoopBackOff` or `Error` when querying `kubectl get pods`. Replicas restart constantly.
*   **Investigation**:
    1. Check exit code and status:
       ```bash
       kubectl describe pod <pod-name> -n ai-services
       ```
    2. Extract logs from current and previous crash cycles:
       ```bash
       kubectl logs <pod-name> -n ai-services --previous --tail=50
       ```
*   **Resolution**: Fix underlying syntax error, missing environment variable, or configuration file path mismatch. Update the manifest and apply.
*   **Prevention**: Implement robust readiness/liveness startup probe delay buffer settings and execute pre-validation staging checks.

---

## 🛠️ Incident 2: Network Failures (Packet Drops)
*   **Symptoms**: Core services timeout when making inter-namespace connections (e.g. FastAPI cannot reach PostgreSQL).
*   **Investigation**:
    1. Probe network connection using temporary debug container:
       ```bash
       kubectl run curl-debug --image=curlimages/curl -i --rm -- sh
       # Inside container, test connection:
       curl -v http://postgres-ha-rw.databases.svc.cluster.local:5432
       ```
    2. Audit namespace NetworkPolicy constraints.
*   **Resolution**: Modify `network-policies.yaml` to explicitly authorize TCP communication between the target pods on port `5432` / `9092`.
*   **Prevention**: Write automated test specs using validation tools during CI to assert connectivity mappings.

---

## 🛠️ Incident 3: DNS Resolution Failures
*   **Symptoms**: Service discovery names (like `postgres-ha-rw.databases.svc.cluster.local`) fail to resolve inside workloads.
*   **Investigation**:
    1. Query CoreDNS pods and configuration status:
       ```bash
       kubectl get pods -n kube-system -l k8s-app=kube-dns
       kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
       ```
    2. Inspect CoreDNS endpoints mapping:
       ```bash
       kubectl get endpoints kube-dns -n kube-system
       ```
*   **Resolution**: Restart CoreDNS deployment to flush network pools or adjust CoreDNS upstream DNS server mappings inside its ConfigMap:
    ```bash
    kubectl rollout restart deployment coredns -n kube-system
    ```
*   **Prevention**: Enable CoreDNS horizontal autoscaling (coredns-autoscaler) to dynamic-scale memory buffers under request spikes.

---

## 🛠️ Incident 4: Kafka Broker Outages
*   **Symptoms**: FastAPI cannot publish records; logs return `KafkaError: Local: Queue full` or bootstrap connections fail.
*   **Investigation**:
    1. Verify Strimzi Kafka cluster state:
       ```bash
       kubectl get kafka -n kafka
       kubectl describe statefulset production-kafka-kafka -n kafka
       ```
    2. Check broker volume consumption:
       ```bash
       kubectl get pvc -n kafka
       ```
*   **Resolution**: Expand broker persistent volume sizes or rebalance broker partitions using `KafkaRebalance` custom resources.
*   **Prevention**: Configure Alertmanager disk utilization alerts to scale storage before disk boundaries reach 80%.

---

## 🛠️ Incident 5: Database Failures (Split-Brain / Outage)
*   **Symptoms**: Database queries return read-only or read/write errors. Postgres primary is unreachable.
*   **Investigation**:
    1. Query CloudNativePG cluster health status:
       ```bash
       kubectl cnpg status postgres-ha -n databases
       ```
    2. View logs of the primary controller manager container:
       ```bash
       kubectl logs postgres-ha-1 -n databases -c manager --tail=100
       ```
*   **Resolution**: Promote a healthy replica pod using `kubectl cnpg promote postgres-ha` or trigger instance recovery from snapshots.
*   **Prevention**: Configure minimum instances count to `3` to guarantee consensus and etcd election success.

---

## 🛠️ Incident 6: High API Latency
*   **Symptoms**: User requests experience latency > 500ms; Prometheus triggers `FastAPIHighLatencyP95` warnings.
*   **Investigation**:
    1. Inspect Jaeger/Tempo distributed spans to pinpoint bottleneck block (e.g. DB transaction wait time vs network latency).
    2. Check CPU throttling metrics:
       ```bash
       kubectl top pods -n ai-services
       ```
*   **Resolution**: Remove or increase CPU cgroup limits (set limits to `2x` or `3x` of CPU requests) to avoid linux kernel CFS throttling.
*   **Prevention**: Set up Vertical Pod Autoscaler (VPA) in recommendation mode to continuously right-size limits.

---

## 🛠️ Incident 7: Platform Cost Overruns
*   **Symptoms**: Monthly cloud bill exceeds allocated budget due to overprovisioned idle nodes and resource waste.
*   **Investigation**:
    1. Run Kubecost dashboards or query resource slack metrics:
       ```promql
       sum(kube_pod_container_resource_requests{resource="cpu"}) - sum(rate(container_cpu_usage_seconds_total[1h]))
       ```
*   **Resolution**: Configure Karpenter NodePool consolidation policy and write a CronJob to scale down dev deployments off-hours.
*   **Prevention**: Define resource quotas per namespace and enforce strict sizing limits at CI stage.

---

## 🛠️ Incident 8: Autoscaling Coordination Failures (Node Exhaustion)
*   **Symptoms**: HPA demands replicas scale up, but pods remain stuck in `Pending` and no new nodes join the cluster.
*   **Investigation**:
    1. Search pending pod events:
       ```bash
       kubectl get events --sort-by='.metadata.creationTimestamp' -n ai-services
       ```
    2. Review Karpenter pod controller logs:
       ```bash
       kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100
       ```
*   **Resolution**: Verify AWS IAM OIDC roles for Karpenter or modify NodePool subnet discovery selectors to match active subnets.
*   **Prevention**: Add pre-warmed, low-priority "pause" pods (using PriorityClass) to reserve spare capacity for instant scale-outs.

---

## 🛠️ Incident 9: ArgoCD Sync Failures (Resource Drift)
*   **Symptoms**: ArgoCD application shows status `OutOfSync` or `Degraded`. Manual changes to resources are immediately reverted or blocked.
*   **Investigation**:
    1. Identify drift details in ArgoCD:
       ```bash
       kubectl get app production-platform-gitops -n argocd -o jsonpath='{.status.resources}'
       ```
*   **Resolution**: Check Git repository code for syntactical errors, or override drift behavior by turning off `selfHeal` temporarily. Commit the corrected manifest to trigger automated synchronization.
*   **Prevention**: Protect manifest branches via branch protection rules and validate YAML linting on all pull requests.

---

## 🛠️ Incident 10: Ingress SSL Certificate Expiration
*   **Symptoms**: Browsers display `NET::ERR_CERT_DATE_INVALID` when users connect to the platform URL.
*   **Investigation**:
    1. Check cert-manager Certificate resource state:
       ```bash
       kubectl get certificate -n ai-services
       kubectl describe order -n ai-services
       ```
*   **Resolution**: Force cert-manager to trigger instant certificate renewal:
    ```bash
    kubectl cert-manager renew fastapi-ai-tls -n ai-services
    ```
*   **Prevention**: Monitor Let's Encrypt renewal events and configure alert notifications for certificates expiring in less than 20 days.

---

## 🛠️ Incident 11: Security Incidents (Malicious Pod Access)
*   **Symptoms**: Pods exhibit abnormal outbound traffic to unknown public IPs; unauthorized shell executions detected.
*   **Investigation**:
    1. Audit active API server exec events:
       ```bash
       kubectl get events -n ai-services | grep -i "exec"
       ```
    2. Verify NetworkPolicy rules matching target pod namespace.
*   **Resolution**: Immediately terminate the compromised container pod and restrict its network access by applying a strict network deny-all policy:
    ```bash
    kubectl scale deployment/fastapi-ai-service --replicas=0 -n ai-services
    ```
*   **Prevention**: Lock down container runtimes using read-only root filesystems and drop all unnecessary Linux capabilities.
