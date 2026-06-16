# 🛠️ Lab 4: Global Traffic Routing & GeoDNS Configuration

In this lab, you will configure a global load-balancing ingress using CoreDNS GeoIP plugin simulations. This allows routing clients to the closest cluster based on their IP address location.

---

## 🏗️ Step 1: Deploy Global Ingress Resources

First, deploy the GSLB-configured ingress onto both the `east` and `west` clusters.

1.  **Apply to East**:
    ```bash
    kubectl apply -f ../manifests/ingress-global-gslb.yaml --context east
    ```
2.  **Apply to West**:
    ```bash
    kubectl apply -f ../manifests/ingress-global-gslb.yaml --context west
    ```

---

## 🔌 Step 2: Understand the CoreDNS GeoIP Simulation

In a real enterprise environment, Route53 or Cloudflare GSLB manages this. Locally, we will simulate this by configuring a CoreDNS instance patched with the `geoip` plugin.

Consider this CoreDNS `Corefile` configuration:

```nginx
global.company.com:53 {
    log
    errors
    # GeoIP database plugin initialization
    geoip /etc/coredns/GeoIP.dat {
        # Define geographic zones mapped to cluster ingress IPs
        US  192.0.2.10  # kind-east Ingress Controller IP
        EU  198.51.100.20 # kind-west Ingress Controller IP
        default 192.0.2.10
    }
}
```

---

## 🧪 Step 3: Test GeoIP Resolution using EDNS Client Subnet

To verify if the DNS server resolves names correctly depending on the user's location, we use `dig` with **EDNS Client Subnet (ECS)** flags. This allows us to pass a mock client IP to the DNS query.

1.  **Simulate a user query originating from Paris, France (IP: `194.0.0.1`)**:
    We query the DNS server specifying the subnet `194.0.0.0/24`:
    ```bash
    dig @localhost -p 1053 api.global.company.com +subnet=194.0.0.0/24
    ```
    *Expected Output*:
    ```
    ;; ANSWER SECTION:
    api.global.company.com.  30  IN  A  198.51.100.20
    ```
    > [!NOTE]
    > CoreDNS successfully resolved the French IP to the **European ingress point** (`198.51.100.20`).

2.  **Simulate a user query originating from Virginia, USA (IP: `54.210.0.1`)**:
    We query the DNS server specifying the subnet `54.210.0.0/24`:
    ```bash
    dig @localhost -p 1053 api.global.company.com +subnet=54.210.0.0/24
    ```
    *Expected Output*:
    ```
    ;; ANSWER SECTION:
    api.global.company.com.  30  IN  A  192.0.2.10
    ```
    > [!NOTE]
    > CoreDNS successfully resolved the US IP to the **US ingress point** (`192.0.2.10`).

---

## 📈 Step 4: Verify Failover State Routing

If the GSLB controller detects that the European cluster is offline (via HTTP probes on the `/healthz` path), it dynamically updates the DNS records.

Even if a European client queries the DNS server, the GSLB controller overrides the GeoIP database and returns the US IP:

```bash
# Querying for Europe user while EU cluster is offline
dig @localhost -p 1053 api.global.company.com +subnet=194.0.0.0/24
```
*Expected Output*:
```
;; ANSWER SECTION:
api.global.company.com.  30  IN  A  192.0.2.10
```
This confirms that traffic is steered safely around degraded regions.
