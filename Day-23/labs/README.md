# Day 23 Hands-On Labs: Service Mesh Deep Dive

Welcome to the hands-on labs for Day 23. Today, you will act as a Lead Platform Engineer to install, configure, secure, and debug service meshes (Istio and Linkerd) in a local Kubernetes environment.

---

## 🛠️ Lab Directory

1.  **[Lab 1: Installing Istio via istioctl & Operator](file:///d:/30_Days_of_Production_Kubernetes/Day-23/labs/lab-1-install-istio.md)**  
    Learn how to install Istio, configure components, and manage the Control Plane lifecycle.
2.  **[Lab 2: Installing Linkerd](file:///d:/30_Days_of_Production_Kubernetes/Day-23/labs/lab-2-install-linkerd.md)**  
    Install Linkerd, run pre-flight checks, and explore its lightweight dashboard tools.
3.  **[Lab 3: Configure Sidecar Injection](file:///d:/30_Days_of_Production_Kubernetes/Day-23/labs/lab-3-sidecar-injection.md)**  
    Inject Envoy and linkerd-proxies into workload pods and inspect the resulting network namespaces.
4.  **[Lab 4: Enforce Mutual TLS (mTLS)](file:///d:/30_Days_of_Production_Kubernetes/Day-23/labs/lab-4-enable-mtls.md)**  
    Configure PeerAuthentication policy modes and audit encrypted traffic states using CLI tools.
5.  **[Lab 5: L7 Traffic Routing & Canary Releases](file:///d:/30_Days_of_Production_Kubernetes/Day-23/labs/lab-5-traffic-routing-canary.md)**  
    Deploy multi-version backend instances and execute fine-grained canary splits using VirtualServices.
6.  **[Lab 6: Configure Authorization Policies](file:///d:/30_Days_of_Production_Kubernetes/Day-23/labs/lab-6-authorization-policies.md)**  
    Restrict service access to specific client identities on specific HTTP endpoints.
7.  **[Lab 7: Implement Zero-Trust Networking](file:///d:/30_Days_of_Production_Kubernetes/Day-23/labs/lab-7-zero-trust.md)**  
    Layer PeerAuthentication and AuthorizationPolicies to establish a secure perimeter.
8.  **[Lab 8: Production Operations & Debugging](file:///d:/30_Days_of_Production_Kubernetes/Day-23/labs/lab-8-production-operations.md)**  
    Use `istioctl proxy-config`, inspect Envoy xDS dumps, analyze configuration latency, and run diagnostic queries.

---

## 📋 Prerequisites
*   A running Kubernetes cluster (Kind, Minikube, or custom dev cluster)
*   `kubectl` installed and configured.
*   `curl` and `jq` installed on your local development machine.
*   Manifests from the [manifests/](file:///d:/30_Days_of_Production_Kubernetes/Day-23/manifests/) folder.
