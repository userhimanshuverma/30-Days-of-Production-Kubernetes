# Lab 2: Tracing Kubernetes API Requests

Kubernetes is entirely REST-API driven. In this lab, you will audit the raw REST requests made by `kubectl` under the hood using verbosity flags, and then execute a raw `curl` request directly to the API Server.

---

## 🏃 Step 1: Analyze kubectl Verbosity Levels
The `kubectl` CLI provides a `-v` (verbosity) flag that exposes the underlying HTTP exchanges.

| Verbosity Level | Output Details |
|---|---|
| `-v=6` | Displays requested URLs, HTTP methods, and response codes. |
| `-v=8` | Adds HTTP request/response headers and curl command equivalents. |
| `-v=9` | Adds raw response bodies (JSON payloads) and detailed transaction logs. |

Run a list command with level 6:
```bash
kubectl get nodes -v=6
```

**Expected Output:**
```
I0525 14:10:15.102345    8912 loader.go:374] Config loaded from file:  /home/user/.kube/config
I0525 14:10:15.145322    8912 round_trippers.go:553] GET https://127.0.0.1:44321/api/v1/nodes?limit=500 200 OK in 42 milliseconds
```
*Note the REST path: `/api/v1/nodes`.*

Run the same command with level 8 to view the HTTP headers:
```bash
kubectl get nodes -v=8
```

**Expected Output (Truncated):**
```
I0525 14:12:02.102322    9051 round_trippers.go:463] GET https://127.0.0.1:44321/api/v1/nodes?limit=500
I0525 14:12:02.102350    9051 round_trippers.go:469] Request Headers:
I0525 14:12:02.102362    9051 round_trippers.go:472]     Accept: application/json;as=Table;v=v1;g=meta.k8s.io,application/json;as=Table;v=v1beta1;g=meta.k8s.io,application/json
I0525 14:12:02.102371    9051 round_trippers.go:472]     User-Agent: kubectl/v1.28.2 (linux/amd64) kubernetes/89a41a3
I0525 14:12:02.148322    9051 round_trippers.go:574] Response Status: 200 OK in 45 milliseconds
I0525 14:12:02.148342    9051 round_trippers.go:577] Response Headers:
I0525 14:12:02.148350    9051 round_trippers.go:580]     Content-Type: application/json
I0525 14:12:02.148358    9051 round_trippers.go:580]     Date: Mon, 25 May 2026 14:12:02 GMT
```

Notice that `kubectl` requests `application/json;as=Table`. This tells the API Server to format the response columns so the CLI can render them directly into the ASCII tables you see on your terminal!

---

## 🏃 Step 2: Extract Secrets and Call the API Server Directly
Let's make a raw REST request to the API Server without using `kubectl`. To do this, we need:
1. The **API Server Endpoint URL**
2. An **Authentication Token** (we will use a ServiceAccount token)
3. The **CA Certificate** to validate the API Server's TLS certificate.

First, let's find our API Server address:
```bash
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
```
*Assume it returns: `https://127.0.0.1:44321`*

Next, create a temporary ServiceAccount and generate a token:
```bash
# Create Service Account
kubectl create serviceaccount api-explorer-sa -n default

# Create a ClusterRoleBinding to grant cluster admin permissions to this SA
kubectl create clusterrolebinding api-explorer-binding --clusterrole=cluster-admin --serviceaccount=default:api-explorer-sa

# Request a token for this Service Account
kubectl create token api-explorer-sa -n default
```
*Copy the printed long JWT token string. Let's export it as a variable:*
```bash
export TOKEN="<YOUR_TOKEN_STRING>"
```

Now, let's extract the cluster CA certificate so our curl client trusts the server:
```bash
kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
```

Now, construct the raw `curl` API query. We will list all Pods in the `default` namespace:
```bash
# Get the API Server address from configuration
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Make the REST call
curl --cacert ca.crt -H "Authorization: Bearer $TOKEN" $APISERVER/api/v1/namespaces/default/pods
```

**Expected Output:**
```json
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {
    "resourceVersion": "24912"
  },
  "items": []
}
```

---

## 🏃 Step 3: Test API Schema Validation
Let's see what happens if we attempt to POST an invalid payload directly to the API Server. 

We will try to create a pod with an invalid `apiVersion`. Create a file named `bad-pod.json`:
```json
{
  "apiVersion": "v1-invalid-version",
  "kind": "Pod",
  "metadata": {
    "name": "invalid-pod"
  },
  "spec": {
    "containers": [
      {
        "name": "nginx",
        "image": "nginx"
      }
    ]
  }
}
```

Attempt to post this JSON object to the API Server:
```bash
curl -X POST --cacert ca.crt \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @bad-pod.json \
  $APISERVER/api/v1/namespaces/default/pods
```

**Expected Output:**
```json
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "Pod in version \"v1\" cannot be handled as a Pod: json: cannot unmarshal string into Go struct field Pod.apiVersion of type string",
  "reason": "BadRequest",
  "code": 400
}
```

### Analysis:
The request was intercepted at the **Schema Validation** layer of the API Server's pipeline. The backend validation routines rejected the request prior to calling mutating or validating webhooks, and long before etcd was contacted.

Clean up the temporary resources:
```bash
kubectl delete clusterrolebinding api-explorer-binding
kubectl delete serviceaccount api-explorer-sa -n default
rm ca.crt bad-pod.json
```
