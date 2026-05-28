# 🛠️ Lab 6: Exploring Endpoints & EndpointSlices

In this lab, you will inspect how Kubernetes translates Pod IP addresses into active routing lists using `Endpoints` and `EndpointSlice` resources, and watch them update dynamically during scale operations.

---

## Step 1: Query the Service Endpoints
List the legacy Endpoints resource for our service:
```bash
kubectl get endpoints web-backend-service
```

**Expected Output**:
```text
NAME                  ENDPOINTS                                                   AGE
web-backend-service   10.244.1.5:8080,10.244.1.6:8080,10.244.2.12:8080            10m
```

---

## Step 2: Query the Modern EndpointSlice Resource
Kubernetes compiles the endpoints into EndpointSlice resources for scalable distribution. List the slices:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web-backend-service
```

**Expected Output**:
```text
NAME                        ADDRESSTYPE   PORTS   ENDPOINTS                  AGE
web-backend-service-gkqf2   IPv4          8080    10.244.1.5,10.244.1.6 + 1  10m
```

Let's inspect the JSON/YAML representation of the EndpointSlice:
```bash
kubectl get endpointslice -l kubernetes.io/service-name=web-backend-service -o yaml
```

**Expected Output (Truncated)**:
```yaml
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  labels:
    kubernetes.io/service-name: web-backend-service
  name: web-backend-service-gkqf2
addressType: IPv4
ports:
  - name: http
    port: 8080
    protocol: TCP
endpoints:
  - addresses:
      - 10.244.1.5
    conditions:
      ready: true
    targetRef:
      kind: Pod
      name: web-backend-7bd5c85b54-jkg8f
  - addresses:
      - 10.244.1.6
    conditions:
      ready: true
    targetRef:
      kind: Pod
      name: web-backend-7bd5c85b54-ffp2x
```

Each endpoint entry explicitly displays the Pod IP, whether the Pod condition is `ready: true` (based on readiness probes), and a reference back to the original Pod resource.

---

## Step 3: Scale the Deployment and Watch updates
Let's open a watch session on the EndpointSlice:
```bash
kubectl get endpointslices -l kubernetes.io/service-name=web-backend-service --watch
```

In a second terminal window, scale the deployment from 3 replicas to 5:
```bash
kubectl scale deployment web-backend --replicas=5
```

Return to your first terminal window. You will see the EndpointSlice automatically detect the new Pod IPs as soon as they pass their readiness probes:

**Watch Output**:
```text
web-backend-service-gkqf2   IPv4   8080   10.244.1.5,10.244.1.6 + 1        10m
web-backend-service-gkqf2   IPv4   8080   10.244.1.5,10.244.1.6 + 2        10m
web-backend-service-gkqf2   IPv4   8080   10.244.1.5,10.244.1.6,10.244.1.8 + 2   10m
```

Scale the deployment back down to 3:
```bash
kubectl scale deployment web-backend --replicas=3
```

Observe that the EndpointSlice automatically removes the terminated Pod IPs from the active endpoint routing list.
