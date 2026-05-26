# 🛠️ Lab 3: Sequential Init Container Dependencies
## 30 Days of Production Kubernetes — Day 4

In this lab, you will deploy an application Pod that relies on an init container to verify database reachability. You will witness the Pod blocking, inspect its wait state, and resolve the dependency to trigger successful application startup.

---

## 🎯 Lab Objectives
1. Deploy a Pod with a dependency check init container.
2. Observe the Pod stuck in `Init:0/1` status.
3. Fetch logs from a running init container.
4. Spin up the missing dependency and watch the Pod automatically reconcile and boot.

---

## 🛠️ Step-by-Step Guide

### Step 1: Deploy the Init Container Pod
Apply the manifest file `manifests/03-init-container.yaml`:
```bash
kubectl apply -f manifests/03-init-container.yaml
```

**Expected Output:**
```text
pod/app-with-init-db created
service/db-service created
```

### Step 2: Observe the Blocked State
Query the status of the Pod:
```bash
kubectl get pods
```

**Expected Output:**
```text
NAME               READY   STATUS     RESTARTS   AGE
app-with-init-db   0/1     Init:0/1   0          25s
```
The status `Init:0/1` indicates that the Pod has 1 init container, and `0` have completed successfully. The application server container (`app-server`) has not started and is blocked.

### Step 3: Inspect Init Container Logs
Why is it blocked? Let's check the logs of the init container `wait-for-postgres`:
```bash
kubectl logs app-with-init-db -c wait-for-postgres
```

**Expected Output:**
```text
Waiting for PostgreSQL service (db-service:5432) to be ready...
Waiting for PostgreSQL service (db-service:5432) to be ready...
Waiting for PostgreSQL service (db-service:5432) to be ready...
```
The script inside the init container is loop-checking connection status to `db-service` using `nc -z`. Because no database is listening on that service port, the check fails.

### Step 4: Resolve the Dependency
Let's launch a temporary pod that listens on port `5432` and labels it so that it acts as the endpoint for `db-service`.

1. **Launch a mock database pod:**
   ```bash
   kubectl run mock-db-pod --image=alpine --labels="app=db-backend" --command -- sh -c "nc -lk -p 5432"
   ```

2. **Wait and observe the application transition:**
   ```bash
   kubectl get pods -w
   ```

**Expected Output Transitions:**
```text
NAME               READY   STATUS     RESTARTS   AGE
app-with-init-db   0/1     Init:0/1   0          2m
app-with-init-db   0/1     PodInitializing   0          2m10s
app-with-init-db   1/1     Running    0          2m12s
```

* **What happened?**
  1. Once `mock-db-pod` booted and bound to port `5432`, the init container `wait-for-postgres` in `app-with-init-db` successfully established a TCP connection.
  2. The init container exited with status code `0`.
  3. The Kubelet transitioned the Pod status to `PodInitializing`, indicating it was pulling and booting the main container.
  4. Finally, the main `app-server` started, transitioning the status to `Running`.

### Step 5: Clean Up
```bash
kubectl delete pod app-with-init-db mock-db-pod
kubectl delete service db-service
```
