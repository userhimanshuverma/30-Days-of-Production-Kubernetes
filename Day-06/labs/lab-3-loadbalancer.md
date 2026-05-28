# 🛠️ Lab 3: Configuring LoadBalancer Services

In this lab, you will deploy a LoadBalancer Service, examine how it integrates with cloud providers, and configure traffic policies to preserve client IP addresses.

---

## Step 1: Deploy the LoadBalancer Service
Apply the LoadBalancer manifest:
```bash
kubectl apply -f manifests/03-loadbalancer-service.yaml
```

**Expected Output**:
```text
service/web-backend-loadbalancer created
```

---

## Step 2: Track Provisioning Status
Examine the service status:
```bash
kubectl get svc web-backend-loadbalancer --watch
```

**Expected Output (Transition)**:
```text
NAME                     TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
web-backend-loadbalancer LoadBalancer   10.98.241.11   <pending>     80:31254/TCP   5s
web-backend-loadbalancer LoadBalancer   10.98.241.11   34.120.44.82  80:31254/TCP   45s
```

* **Note**: If you are running locally (like Kind or Minikube) without a cloud controller or a load-balancer provisioner (like MetalLB), the `EXTERNAL-IP` will remain in `<pending>` indefinitely.
* **Minikube Solution**: In a separate terminal, run `minikube tunnel` to provision a local external IP.
* **Kind Solution**: Install **MetalLB** in your Kind cluster to allocate local virtual IPs.

Once the `EXTERNAL-IP` is active, test it from your local machine:
```bash
curl http://34.120.44.82
```

---

## Step 3: Inspect externalTrafficPolicy
Let's look at the configuration of our LoadBalancer service:
```bash
kubectl get svc web-backend-loadbalancer -o jsonpath='{.spec.externalTrafficPolicy}'
```

**Expected Output**:
```text
Local
```

Because we set `externalTrafficPolicy: Local`:
1. The service only routes traffic to pods on the node that receives the traffic.
2. It preserves the **Client Source IP**.
3. Let's verify this by checking the container logs.

---

## Step 4: Validate Client IP Preservation
Send a request to the load balancer external IP, then inspect the logs of the web-backend pods:

```bash
# Send request
curl http://34.120.44.82

# Read pod logs
kubectl logs -l app=web-backend --tail=20
```

**Expected Output (with Local)**:
You will see your developer machine's real public/local IP (e.g., `192.168.1.50` or your home router external IP) in the HTTP header logs:
```text
192.168.1.50 - - [28/May/2026:12:30:00 +0000] "GET / HTTP/1.1" 200 651 "-" "curl/7.88.1"
```

If we had used `externalTrafficPolicy: Cluster`, the logged IP would have been the **internal node IP** of the routing worker node (e.g., `172.18.0.3`), hiding the client's identity behind NAT.
