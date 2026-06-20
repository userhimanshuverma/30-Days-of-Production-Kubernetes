# SRE Runbook: Multi-Region Active-Passive Failover

## 📌 Context
Our platform runs an active-passive setup across two regions:
*   **Primary (Active)**: `us-east-1`
*   **Secondary (Standby)**: `us-west-2`

This document details the procedure for promoting the standby site and re-routing user requests in the event of a total primary region outage.

---

## 🚨 Phase 1: Outage Identification
Verify that primary cluster is offline by executing checks on API endpoint health and traffic routing:
1.  **SLA Alerts**: Alertmanager triggers `PrimaryRegionIngressDown` or `PostgresDatabaseUnreachable`.
2.  **Manual Probe**: Run `curl -vI https://ai.platform.company.com/healthz`. If response returns `503 Service Unavailable` or `Connection Timeout`, proceed.

---

## 🔄 Phase 2: Standby Database Promotion
We stream WAL archives to an S3 bucket from `us-east-1`. Under a failover, promote PostgreSQL in `us-west-2` using CloudNativePG:

1.  **Verify backup status in US-West-2**:
    ```bash
    kubectl --context=us-west-2 get bootstrap -n databases
    ```
2.  **Point the CNPG cluster to the last transaction snapshot**:
    CNPG's bootstrap config automatically tracks WAL logs. Execute promote logic:
    ```bash
    kubectl --context=us-west-2 cnpg promote postgres-ha -n databases
    ```
3.  **Monitor Postgres database health**:
    ```bash
    kubectl --context=us-west-2 get pods -n databases -w
    ```
    Ensure that the standby DB instances transition to `Primary` and `Replica` states.

---

## ⚙️ Phase 3: Traffic Routing (DNS Shift)
Reroute user requests from `us-east-1` load balancer to `us-west-2` load balancer using AWS CLI Route53 record updates:

1.  **Execute DNS record modification**:
    Update DNS record sets pointing `ai.platform.company.com` to target the standby load balancer address:
    ```bash
    aws route53 change-resource-record-sets \
      --hosted-zone-id Z3M3L1TO56XX \
      --change-batch file://03-networking/dns-failover-batch.json
    ```
2.  **Flush Local DNS Cache**:
    ```bash
    ipconfig /flushdns # Windows
    # OR
    sudo resolvectl flush-caches # Linux
    ```

---

## 🎯 Phase 4: Post-Failover Verification
Check that client traffic reaches the active standby site successfully:
1.  Verify HTTPS API response:
    ```bash
    curl -vI https://ai.platform.company.com/healthz
    ```
    Verify that return code is `200 OK`.
2.  Verify transactional database logs:
    Ensure FastAPI service writes records to the promoted databases successfully:
    ```bash
    kubectl --context=us-west-2 logs -n ai-services -l app=fastapi-ai-service --tail=50
    ```
