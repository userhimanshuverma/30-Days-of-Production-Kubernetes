# Lab 5: L7 Traffic Routing & Canary Releases

## Goal
Implement L7 traffic shaping using Istio. Configure a 90/10 weight-based traffic split to canary workloads and use request headers to force canary routing for beta testers.

---

## Step 1: Deploy Routing Configurations

Apply the Istio custom routing resources from the `traffic-management/` directory.

1.  Deploy the Ingress Gateway config:
    ```bash
    kubectl apply -f traffic-management/gateway.yaml
    ```
2.  Deploy the DestinationRules defining the `v1` and `v2` subsets:
    ```bash
    kubectl apply -f traffic-management/destination-rule-canary.yaml
    ```
3.  Deploy the VirtualService that defines the splitting weights:
    ```bash
    kubectl apply -f traffic-management/virtual-service-canary.yaml
    ```

---

## Step 2: Validate the Rules configuration

Verify that the configurations were compiled successfully by `istiod`:
```bash
istioctl analyze
```
*Expected Output:*
```
✔ No validation issues found.
```

---

## Step 3: Test Weighted Routing Split

We will run a curl traffic generator from our `frontend-app` to simulate internal users calling the backend.

1.  Identify the frontend pod:
    ```bash
    FRONTEND_POD=$(kubectl get pod -l app=frontend-app -o jsonpath='{.items[0].metadata.name}')
    ```
2.  Execute a loop that makes 20 consecutive HTTP requests to `backend-service`:
    ```bash
    kubectl exec $FRONTEND_POD -c application -- sh -c 'for i in $(seq 1 20); do curl -s http://backend-service:80; echo ""; done'
    ```
3.  Count the output distribution.
    *Expected Output:*
    You should see roughly **18 stable responses** and **2 canary responses**, validating the 90/10 split:
    ```
    Backend Service V1 (Stable)
    Backend Service V1 (Stable)
    Backend Service V1 (Stable)
    Backend Service V2 (Canary)
    ...
    ```

---

## Step 4: Test Header-Based Routing

Now, we will send the header `x-user-type: beta-tester` to force the proxy to route 100% of our requests to the `v2` canary subset.

1.  Execute a call sending the beta tester header:
    ```bash
    kubectl exec $FRONTEND_POD -c application -- curl -s -H "x-user-type: beta-tester" http://backend-service:80
    ```
2.  Verify the response text.
    *Expected Output:*
    ```
    Backend Service V2 (Canary)
    ```
    *(No matter how many times you run this query with the header, it will route to V2, demonstrating L7 header-matching logic).*
