# SRE & Cloud Architect Kubernetes Interview Guide

Ten scenario-based technical questions and answers focusing on deep troubleshooting, performance tuning, and architectural design.

---

## ❓ Question 1: Explain the etcd consensus protocol. What occurs under a network partition (split-brain)?
*   **Answer**: etcd uses the **Raft consensus algorithm**. Raft works by electing a single leader, which manages all state modifications. 
    If a network partition divides a 5-node cluster into a group of 2 nodes and a group of 3 nodes:
    *   The side with 2 nodes cannot contact the leader and cannot form a quorum (requires $\lfloor 5/2 \rfloor + 1 = 3$ nodes). It will reject write transactions.
    *   The side with 3 nodes forms a majority. If the old leader is on this side, it remains leader. If not, the 3 nodes elect a new leader.
    *   Once the partition heals, the nodes with outdated state reconcile by pulling updates from the active quorum group leader.

---

## ❓ Question 2: Why does CPU Throttling occur even if pod average utilization is far below its limit?
*   **Answer**: CPU limits are enforced using the Linux kernel's **Completely Fair Scheduler (CFS) bandwidth control** over a fixed period (default `100ms`). 
    If a pod has a limit of `100m` (0.1 core), it is allowed to consume `10ms` of CPU execution time every `100ms`. If the application experiences micro-burst requests (e.g. multi-threaded JSON parsing requiring 1 core for `15ms` at the start of the window), it will exhaust its `10ms` quota within the first `15ms` and be throttled for the remaining `85ms` of the cycle, despite average utilization over 1 minute looking very low. 
    *   *Remedy*: Increase or remove CPU limits while setting requests to actual values to prevent latency spikes.

---

## ❓ Question 3: What is the difference between Container Exit Code 137 and Exit Code 143?
*   **Answer**: 
    *   **Exit Code 137**: Indicates the container was terminated by a `SIGKILL` (signal 9, $128 + 9 = 137$). This is typically triggered by the host's Linux Out-Of-Memory (OOM) Killer because the cgroup memory limit was breached.
    *   **Exit Code 143**: Indicates the container was terminated by a `SIGTERM` (signal 15, $128 + 15 = 143$). This is standard behavior when Kubernetes performs a rolling update or deletion, sending a graceful termination request.

---

## ❓ Question 4: How does Calico's BGP routing compare to Cilium's eBPF routing?
*   **Answer**: 
    *   **Calico BGP**: Felix configures the Linux IP routing table on the host. Nodes exchange routes natively using BGP routing tables. This allows pods to communicate at wire-speed without wrapper encapsulation.
    *   **Cilium eBPF**: Replaces the kernel's routing tables and iptables lists with custom compiled bytecode programs loaded directly into kernel sockets. It bypasses iptables lookup overhead entirely, routing traffic between containers and host network interfaces immediately, enabling faster service load-balancing and Layer 7 path filtering.

---

## ❓ Question 5: How does cert-manager solve the ACME HTTP-01 challenge?
*   **Answer**: 
    1.  `cert-manager` creates a temporary Pod and a Service in the target namespace.
    2.  It creates a temporary Ingress mapping the path `/.well-known/acme-challenge/<TOKEN>` to that service.
    3.  The ACME provider (e.g., Let's Encrypt) makes an HTTP request to the domain to verify the token.
    4.  Once verified, cert-manager deletes the temporary resources and writes the generated TLS certificate into a Kubernetes secret.

---

## ❓ Question 6: What is the risk of utilizing the 'Immediate' VolumeBindingMode in a StorageClass?
*   **Answer**: Under `Immediate` mode, when a PVC is created, the volume is provisioned right away. The cloud provider allocates the volume in a random availability zone (e.g., `us-east-1a`). When a pod is scheduled later, the scheduler might place it on a node in `us-east-1b` (based on resource capacities). This results in a scheduling failure because the volume cannot be cross-attached to a node in a different availability zone. 
    *   *Solution*: Set `volumeBindingMode: WaitForFirstConsumer` to ensure the volume is provisioned in the zone where the pod is scheduled.

---

## ❓ Question 7: Describe the lifecycle of a request from user browser to a Pod.
*   **Answer**: 
    1.  DNS resolves host address to Ingress LoadBalancer IP.
    2.  The LoadBalancer forwards TLS traffic to the NGINX Ingress controller NodePort/LoadBalancer Service.
    3.  NGINX terminates SSL using the TLS secret and routes the request matching the hostname/path.
    4.  It checks the target ClusterIP Service endpoints and chooses a Pod IP (via `kube-proxy` rules or internal round-robin).
    5.  NGINX proxies the HTTP packet directly to the selected Pod's IP address.

---

## ❓ Question 8: How do you coordinate HPA and Karpenter to prevent node thrashing?
*   **Answer**: HPA handles horizontal replica expansion based on metrics, whereas Karpenter provisions nodes to accommodate pending pods. To prevent thrashing:
    *   Configure `stabilizationWindowSeconds` on the HPA scale-down policy to delay replicas reduction (e.g. 5 minutes).
    *   Configure `consolidateAfter` or `consolidationPolicy` on Karpenter NodePools to delay node termination until the nodes are persistently underutilized.

---

## ❓ Question 9: How does External Secrets Operator (ESO) prevent committing secrets to git?
*   **Answer**: SREs install ESO and configure a `SecretStore` pointing to an external secure vault (Vault, AWS Secrets Manager). An `ExternalSecret` manifest is committed to Git, which acts as a schema reference containing only key mappings. The ESO controller reads this schema, retrieves the actual credentials from Vault dynamically, and writes a standard Kubernetes Base64 secret in the target namespace.

---

## ❓ Question 10: How do you gracefully shut down a Pod without dropping active HTTP connections?
*   **Answer**: 
    1.  Set `terminationGracePeriodSeconds` to a high enough threshold (e.g. 60 seconds).
    2.  Use a `preStop` lifecycle hook to inject a sleep (e.g. `sleep 15`) before the container process receives `SIGTERM`. This gives CoreDNS and the Ingress controller time to propagate service endpoint updates and stop routing new requests to the terminating pod.
    3.  Ensure the container application intercepts `SIGTERM` and completes active request transactions before shutting down.
