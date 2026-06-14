# Day 23 Service Mesh Resource Directory

This document organizes official documentation, architecture whitepapers, and real-world case studies for deep-dive learning.

---

## 📖 Official Documentation
*   **[Istio Documentation](https://istio.io/latest/docs/)**: Reference for all Istio API resources, setup guides, and integration tutorials.
*   **[Linkerd Documentation](https://linkerd.io/2.12/overview/)**: The official guide for Linkerd architecture, CLI commands, and telemetry customization.
*   **[Envoy Proxy Documentation](https://www.envoyproxy.io/docs/envoy/latest/)**: Technical details on Envoy's listeners, filter chains, and xDS API schema.

---

## ⚡ Architecture & Design Specifications
*   **[SPIFFE Specification](https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE-ID.md)**: Cryptographic identity standard description for cloud workloads.
*   **[Envoy Threading Model Whitepaper](https://blog.envoyproxy.io/envoy-threading-model-a8d44b922310)**: Detailed write-up by Matt Klein (Envoy creator) on how the lock-free event loop operates.
*   **[eBPF vs iptables Performance](https://buoyant.io/blog/ebpf-iptables-and-linkerd)**: A benchmark study on CPU reduction and network latency improvements when moving from iptables rules to socket level redirection.

---

## 🛠️ Tools & Extensions
*   **[Argo Rollouts](https://argoproj.github.io/argo-rollouts/)**: Kubernetes Controller for executing automated progressive delivery with Istio and Linkerd integrations.
*   **[Kiali](https://kiali.io/)**: Visual console for exploring Istio topology graphs, traffic routes, health, and policy validations.
*   **[cert-manager](https://cert-manager.io/docs/)**: Automates issuing and renewing certificates from public/private CAs (Let's Encrypt, Vault) to bootstrap mesh credentials.
