# 🚨 Kubernetes Networking Troubleshooting Playbook

This runbook contains 10 highly realistic production troubleshooting scenarios. Use this guide to triage, debug, and resolve internal and external networking issues.

---

## 🧭 General Debugging Flowchart
```
                 [ Networking Issue Detected ]
                              │
             ┌────────────────┴────────────────┐
             ▼                                 ▼
    [ Name Resolution fails ]         [ IP / Port connection fails ]
             │                                 │
    Check CoreDNS Pods & Logs         Check Pod Labels & Selectors
             │                                 │
    Verify /etc/resolv.conf           Verify EndpointSlice resources
             │                                 │
    Verify Upstream DNS forwarding    Check kube-proxy rules / CNI status
```

---

## 🛠️ Troubleshooting Scenarios

### Scenario 1: DNS Query Timeout or Resolution Failure
* **Symptoms**: Applications fail to resolve hostnames, showing errors like `getaddrinfo ENOTFOUND` or `Could not resolve host: web-backend-service`.
* **Root Cause**: CoreDNS pods are overloaded, throttled by CPU limits, or the CoreDNS Service is misconfigured.
* **Investigation**:
  1. Test DNS from the debug pod:
     ```bash
     kubectl exec -it dns-debug -- nslookup web-backend-service
     ```
  2. Check if CoreDNS pods are running and healthy:
     ```bash
     kubectl get pods -n kube-system -l k8s-app=kube-dns
     ```
  3. Inspect CoreDNS deployment logs for errors:
     ```bash
     kubectl logs -n kube-system -l k8s-app=kube-dns --tail=100
     ```
  4. Verify if CPU throttling is occurring (look for throttled time in metrics or high CPU usage).
* **Resolution**:
  * Scale the CoreDNS deployment replicas if resource-starved:
    ```bash
    kubectl scale deployment coredns -n kube-system --replicas=4
    ```
  * Remove or increase restrictive CPU limits on CoreDNS pods to prevent CPU throttling (CoreDNS is highly CPU-sensitive).
* **Prevention**: Deploy `NodeLocal DNSCache` to handle the query load locally and cache responses on worker nodes.

---

### Scenario 2: Service Unreachable (Connection Timeout)
* **Symptoms**: Clients attempt to connect to the Service IP (ClusterIP) but experience connection timeouts or `Connection Refused` errors.
* **Root Cause**: The Service selector does not match any active Pod labels, resulting in an empty Endpoints list.
* **Investigation**:
  1. Describe the Service and check the `Endpoints` line:
     ```bash
     kubectl describe svc web-backend-service
     ```
  2. Check if the selector matches the actual Pod labels:
     ```bash
     kubectl get pods --show-labels
     ```
     Compare the service's `Selector: app=web-backend` against the pod's labels.
  3. Verify that Pods are healthy and in a `Running` state:
     ```bash
     kubectl get pods -l app=web-backend
     ```
     Pods failing readiness probes will be removed from the Endpoints list automatically.
* **Resolution**:
  * Fix label selectors in the Service manifest or update the Pod templates.
  * Resolve application startup or probe failures so Pods transition to `Ready`.
* **Prevention**: Implement CI/CD linter checks (like `kube-linter` or `Conftest`) to ensure label alignment between Deployments and Services.

---

### Scenario 3: kube-proxy CrashLoopBackOff or Rule Sync Stalls
* **Symptoms**: Services work on some nodes but completely fail on others. Newly created Services are unreachable cluster-wide.
* **Root Cause**: `kube-proxy` crashed on specific worker nodes (e.g., due to missing kernel modules for IPVS, or corrupted local iptables state).
* **Investigation**:
  1. Check the health of kube-proxy pods:
     ```bash
     kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
     ```
  2. Read the logs of the crashing kube-proxy pod:
     ```bash
     kubectl logs <kube-proxy-pod-name> -n kube-system
     ```
  3. Check the host's kernel ring buffer on the affected node for Netfilter or IPVS errors:
     ```bash
     dmesg | grep -E "ipvs|netfilter"
     ```
* **Resolution**:
  * If using IPVS mode and the host node is missing IPVS kernel modules (e.g., `ip_vs`, `ip_vs_rr`), load them on the host:
    ```bash
    sudo modprobe ip_vs
    sudo modprobe ip_vs_rr
    ```
  * Restart the kube-proxy pod on the broken node:
    ```bash
    kubectl delete pod <kube-proxy-pod-name> -n kube-system
    ```
* **Prevention**: Add node provisioning scripts (UserData/Ansible) to guarantee necessary network modules are loaded before the Kubelet starts.

---

### Scenario 4: NodePort Inaccessible From Outside the Cluster
* **Symptoms**: External clients cannot connect to `Node-IP:NodePort` (e.g., `192.168.1.10:30080`), receiving connection timeouts.
* **Root Cause**: Node firewall (e.g., firewalld, ufw), security groups (e.g., AWS Security Groups), or corporate firewalls are blocking the NodePort port range (30000-32767).
* **Investigation**:
  1. Test connectivity locally on the node host:
     ```bash
     curl http://localhost:30080
     ```
     If local curl works, kube-proxy routing is correct; the issue is external firewall blocking.
  2. Inspect node security rules. Check if security groups allow TCP port range 30000-32767 from the client source IP.
* **Resolution**:
  * Open the NodePort range (30000-32767) in the cloud provider firewall / security group.
  * If host firewall is enabled, add a rule to allow the port:
    ```bash
    sudo ufw allow 30080/tcp
    ```
* **Prevention**: Keep Kubernetes ingress node pools separate and restrict NodePort access to authorized edge routers or Load Balancers.

---

### Scenario 5: Traffic Imbalance (One Pod Overloaded, Others Idle)
* **Symptoms**: One Pod replica handles 95% of traffic and crashes due to OOM/CPU saturation, while other replicas sit idle.
* **Root Cause**: Persistent connections (gRPC or HTTP/2 keep-alive) route all requests over a single TCP connection, rendering L4 IP-based load balancing ineffective.
* **Investigation**:
  1. Check the active TCP connections on target backend pods:
     ```bash
     kubectl exec -it <pod-name> -- netstat -an | grep :8080 | grep ESTABLISHED
     ```
  2. Compare CPU metrics among the pods to confirm load distribution.
* **Resolution**:
  * Implement **client-side load balancing** in the application client code.
  * Introduce a **Layer 7 Load Balancer / Ingress Controller** (like Nginx, Envoy, or Traefik) that inspects HTTP/2 requests and balances them individually.
* **Prevention**: Set up a Service Mesh (Istio/Linkerd) to manage gRPC traffic distribution natively.

---

### Scenario 6: Pod-to-Pod Communication Failure (Cross-Node)
* **Symptoms**: Pods can ping and curl each other if they reside on the *same node*, but fail to communicate if they are scheduled on *different nodes*.
* **Root Cause**: The CNI network overlay (VXLAN/Geneve) is blocked by security groups (e.g., blocking UDP port 4789), or the host routing table is missing entries for other nodes' subnets.
* **Investigation**:
  1. Identify where pods reside:
     ```bash
     kubectl get pods -o wide
     ```
  2. Try to run traceroute between pods across nodes.
  3. Verify host-to-host connectivity on overlay ports:
     * VXLAN: UDP 4789
     * Calico: IP-in-IP (IP protocol 4) or BGP (TCP 179)
     Use `nc -zuv <other-node-ip> 4789` to verify.
* **Resolution**:
  * Adjust AWS/GCP security groups to permit host-to-host communication on CNI overlay protocol ports.
  * Enable IP forwarding in host kernel if disabled:
    ```bash
    sysctl net.ipv4.ip_forward=1
    ```
* **Prevention**: Build automated network connectivity validation tests into the node provisioning pipeline.

---

### Scenario 7: Endpoint Mismatch / Stale EndpointSlices
* **Symptoms**: Requests occasionally fail with 503 or timeout, but succeed on retry.
* **Root Cause**: A stale EndpointSlice contains the IP of a terminated/deleted Pod, or fails to include a new Pod IP.
* **Investigation**:
  1. List the EndpointSlices associated with the service:
     ```bash
     kubectl get endpointslices -l kubernetes.io/service-name=web-backend-service
     ```
  2. Inspect the slice endpoints and compare with current running Pod IPs:
     ```bash
     kubectl get pods -o wide
     ```
* **Resolution**:
  * Force-trigger EndpointSlice reconciliation by deleting the EndpointSlice resource; the Controller Manager will recreate it instantly:
    ```bash
    kubectl delete endpointslice <slice-name>
    ```
* **Prevention**: Monitor API Server health and Controller Manager latency metrics.

---

### Scenario 8: Cloud LoadBalancer Failing to Provision
* **Symptoms**: The LoadBalancer Service remains in `<pending>` state indefinitely under `EXTERNAL-IP`.
* **Root Cause**: The Kubernetes Cluster lacks cloud provider credentials (missing IAM roles), is hitting cloud resource limits (IP quota exceeded), or lacks subnet tags.
* **Investigation**:
  1. Describe the Service and read the `Events` section:
     ```bash
     kubectl describe svc web-backend-loadbalancer
     ```
     Look for errors like `FailedToCreateLoadBalancer` or `AccessDenied`.
  2. Verify subnet tagging. In AWS, subnets must be tagged with `kubernetes.io/cluster/<cluster-name>: shared` and `kubernetes.io/role/elb: 1`.
* **Resolution**:
  * Add the appropriate tags to the target VPC subnets.
  * Fix IAM role permissions assigned to the Cloud Controller Manager.
* **Prevention**: Deploy infrastructure using Terraform to ensure subnets, IAM roles, and tags are provisioned automatically.

---

### Scenario 9: NetworkPolicy Blocking Unexpected System Traffic
* **Symptoms**: Pods fail to resolve DNS names and cannot connect to any external services or even internal databases.
* **Root Cause**: A restrictive default-deny NetworkPolicy was applied to the namespace, blocking outbound DNS traffic to CoreDNS.
* **Investigation**:
  1. List NetworkPolicies in the namespace:
     ```bash
     kubectl get netpol
     ```
  2. Check if a default-deny egress policy exists.
  3. Confirm if egress to the `kube-system` namespace on UDP/TCP port 53 is allowed.
* **Resolution**:
  * Add a policy rule to permit egress DNS queries to CoreDNS:
    ```yaml
    egress:
    - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
      ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
    ```
* **Prevention**: Create standard namespace templates that include base policy rules for core system dependencies.

---

### Scenario 10: Hairpin-NAT / Loopback Connection Failure
* **Symptoms**: A Pod tries to call a Service that routes to itself, but the connection times out.
* **Root Cause**: Hairpin mode is disabled in the CNI or Kubelet, preventing a pod from routing traffic back to itself via a Service VIP.
* **Investigation**:
  1. Exec into the pod and try to call the service VIP:
     ```bash
     curl http://<service-ip>:<port>
     ```
  2. Verify if the target IP resolves to the pod's own IP address.
* **Resolution**:
  * Enable hairpin mode in the Kubelet configuration (`hairpinMode: hairpin-veth` or `promiscuous-bridge`).
  * Alternatively, modify the architecture so Pods communicate locally via localhost rather than using the Service virtual IP.
* **Prevention**: Verify Hairpin-NAT support during CNI selection and node bootstrapping validation.
