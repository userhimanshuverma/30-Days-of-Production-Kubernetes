# Platform SRE Operations Cheat Sheet

A compilation of diagnostic command patterns for operating and troubleshooting the Kubernetes platform.

---

## ☸️ General Cluster Operations
*   Get pod resource usage sorted by CPU:
    ```bash
    kubectl top pods -A --sort-by=cpu
    ```
*   View all events sorted by timestamp:
    ```bash
    kubectl get events -A --sort-by='.metadata.creationTimestamp'
    ```
*   Inspect container env variables:
    ```bash
    kubectl exec -n ai-services <pod-name> -- printenv
    ```

---

## 🔒 Certificate & TLS Debugging
*   Check cert-manager certificate issue logs:
    ```bash
    kubectl describe certificate -n ai-services
    kubectl logs -n cert-manager -l app=cert-manager --tail=100
    ```
*   Verify Secret certificate content dates:
    ```bash
    kubectl get secret fastapi-ai-tls -n ai-services -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text | grep -A2 "Validity"
    ```

---

## 💾 Stateful DB & Kafka Operations
*   Promote CNPG Postgres replica pod:
    ```bash
    kubectl cnpg promote postgres-ha -n databases
    ```
*   Monitor CNPG database replication lag:
    ```bash
    kubectl cnpg status postgres-ha -n databases
    ```
*   Describe topic settings in Strimzi:
    ```bash
    kubectl describe kafkatopic inference-events -n kafka
    ```
*   Consume messages inside Kafka broker:
    ```bash
    kubectl exec -n kafka -it production-kafka-kafka-0 -- bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic inference-events --from-beginning
    ```

---

## 🔄 ArgoCD & GitOps Debugging
*   Reconcile and sync ArgoCD Application manually:
    ```bash
    kubectl patch app production-platform-gitops -n argocd -p '{"spec":{"source":{"targetRevision":"HEAD"}}}' --type=merge
    ```
*   Inspect app synchronization logs:
    ```bash
    kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
    ```
