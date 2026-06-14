# Lab 8: Production Operations & Debugging

## Goal
Master the day-2 diagnostic utilities used to operate and troubleshoot service meshes at scale. Learn how to inspect Envoy routing tables, verify endpoint syncing, and monitor sidecar resource metrics.

---

## Tool 1: Check Config Synchronization (`istioctl proxy-status`)

When you apply a routing manifest (like a VirtualService), Pilot compiles and pushes it. Verify that the proxy sidecars have successfully synchronized the latest configurations:

```bash
istioctl proxy-status
```
*Expected Output:*
```
NAME                                                   CDS        LDS        EDS        RDS        ISTIOD                      VERSION
frontend-app-695c8c6fbc-xyz12.default                  SYNCED     SYNCED     SYNCED     SYNCED     istiod-7b968bc7f-8rwx9      1.18.0
backend-v1-7cdbc8c7fb-abc12.default                    SYNCED     SYNCED     SYNCED     SYNCED     istiod-7b968bc7f-8rwx9      1.18.0
```
*If a proxy shows `STALE` for more than a few seconds, it indicates a communication issue between the sidecar and istiod.*

---

## Tool 2: Inspect Envoy Routing Tables (`istioctl proxy-config`)

You can query Envoy directly to see exactly how it processes requests.

1.  Identify the frontend pod:
    ```bash
    FRONTEND_POD=$(kubectl get pod -l app=frontend-app -o jsonpath='{.items[0].metadata.name}')
    ```
2.  List all L7 routes loaded on the proxy:
    ```bash
    istioctl proxy-config routes $FRONTEND_POD
    ```
3.  Examine the detailed HTTP route definitions targeting the `backend-service`:
    ```bash
    istioctl proxy-config routes $FRONTEND_POD --name 80 -o json
    ```
    *Find the `weightedClusters` list in the output and verify that it matches the 90/10 weight configurations from your VirtualService.*

---

## Tool 3: Verify Dynamic Endpoints (EDS)

To check the pod IP endpoints that Envoy will balance traffic across:

```bash
istioctl proxy-config endpoints $FRONTEND_POD | grep backend-service
```
*Expected Output:*
```
10.244.1.15:8080                 HEALTHY     outbound|80||backend-service.default.svc.cluster.local
10.244.2.22:8080                 HEALTHY     outbound|80||backend-service.default.svc.cluster.local
10.244.2.23:8080                 HEALTHY     outbound|80||backend-service.default.svc.cluster.local
```
*Compare these IP addresses against your running pods (`kubectl get pods -o wide`). They should align. If they don't, check endpoint sync channels.*

---

## Tool 4: Access Envoy Administration Dashboard

Envoy sidecars run a local administrative API on port `15000`. You can expose it via port-forward to run audits:

1.  Start a port-forward to the frontend pod's Envoy admin port:
    ```bash
    kubectl port-forward $FRONTEND_POD 15000:15000
    ```
2.  In a separate terminal, curl the admin dashboard endpoints:
    *   **Get CPU Profiling / Thread Info**: `curl http://localhost:15000/server_info`
    *   **Trigger Configuration Dump**: `curl http://localhost:15000/config_dump`
    *   **List Active Clusters**: `curl http://localhost:15000/clusters`
    *   **List Metrics**: `curl http://localhost:15000/stats/prometheus`

3.  Terminate the port-forward when completed (`Ctrl+C`).
