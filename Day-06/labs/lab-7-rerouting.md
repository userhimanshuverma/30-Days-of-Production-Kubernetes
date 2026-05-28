# 🛠️ Lab 7: Simulating Pod Failures & Traffic Rerouting

In this lab, you will intentionally terminate backend Pods while running continuous load to observe how the Kubernetes Control Plane handles network failures and how to achieve zero-downtime releases.

---

## Step 1: Run Continuous Internal Traffic
We will run a loop that continuously queries our Service. Execute this script inside the `dns-debug` container:

```bash
kubectl exec -it dns-debug -- /bin/sh -c 'while true; do curl -s --connect-timeout 1 -o /dev/null -w "%{http_code}\n" http://web-backend-service; sleep 0.1; done'
```

This command queries the service every 100 milliseconds and prints the HTTP status code (expected: `200`).

---

## Step 2: Delete a Pod and Watch the Traffic
While the loop is running, open a second terminal window and delete one of the backend Pods:

```bash
# List active pods
kubectl get pods -l app=web-backend

# Delete one of the pods
kubectl delete pod <pod-name-from-above>
```

Return to your first terminal window and observe the curl output.

**What you will see**:
Depending on the speed of your local cluster, you will likely see a few requests fail with `000` (timeout/refused) or `502`/`503` errors before returning to stable `200`s:
```text
200
200
000
Connection refused
000
200
200
```

---

## Step 3: Analyze the Propagation Delay
Why did requests fail?
1. The Pod was deleted. The Kubelet immediately sent `SIGTERM` to the application.
2. The application stopped listening or exited.
3. However, it takes a few seconds for the EndpointSlice Controller to detect this, update the API, and for `kube-proxy` on all worker nodes to rebuild and reload the NAT rules.
4. During this gap (typically 1 to 5 seconds), traffic was still routed to the dead Pod's IP.

---

## Step 4: Fix the Failure with a `preStop` Hook
To prevent this routing gap, we can add a `preStop` hook to the deployment. The hook instructs the container to sleep before shutting down, allowing the endpoints update to propagate.

Let's edit the Deployment to include a `preStop` hook. Run this command to update the deployment:

```bash
kubectl patch deployment web-backend --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/lifecycle", "value": {"preStop": {"exec": {"command": ["sleep", "15"]}}}}]'
```

Wait for the rolling update to complete:
```bash
kubectl rollout status deployment web-backend
```

---

## Step 5: Test Deletion Again
Restart the traffic loop in Terminal 1:
```bash
kubectl exec -it dns-debug -- /bin/sh -c 'while true; do curl -s --connect-timeout 1 -o /dev/null -w "%{http_code}\n" http://web-backend-service; sleep 0.1; done'
```

In Terminal 2, delete a new pod:
```bash
kubectl get pods -l app=web-backend
kubectl delete pod <new-pod-name>
```

Examine Terminal 1.

**Expected Outcome**:
This time, you will observe **100% success (all `200`s)**. No connections are dropped! Because of the `sleep 15` preStop hook:
1. The EndpointSlice was updated and kube-proxy removed the pod from the routing rules *before* the application container received the shutdown signal.
2. Zero requests were routed to the terminating Pod after it began shutting down.
