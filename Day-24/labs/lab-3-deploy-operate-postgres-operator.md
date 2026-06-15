# 🛠️ Lab 3: In-Cluster Operator Deployment & Day-2 Operations

## Overview
In this lab, you will deploy the custom `PostgresCluster` operator inside your Kubernetes cluster. You will then perform common Day-2 database administrator tasks including scaling, triggering automated self-healing, rolling out software upgrades, and executing backup snapshots.

---

## Exercise 1: Deploying the Operator

We will use the Kubernetes manifests created in `manifests/` to deploy the ServiceAccount, ClusterRole bindings, and the deployment running the operator.

### 1. Apply RBAC and Deployment Configurations
```bash
kubectl apply -f manifests/operator-rbac-deployment.yaml
```

*Expected Output:*
```text
serviceaccount/postgres-operator-sa created
clusterrole.rbac.authorization.k8s.io/postgres-operator-role created
clusterrolebinding.rbac.authorization.k8s.io/postgres-operator-role-binding created
deployment.apps/postgres-operator created
```

### 2. Verify Operator Health
Ensure the operator deployment is healthy and ready:
```bash
kubectl get deployment postgres-operator
```

*Expected Output:*
```text
NAME                READY   UP-TO-DATE   AVAILABLE   AGE
postgres-operator   1/1     1            1           30s
```

Check the logs of the running operator manager:
```bash
kubectl logs -f deployment/postgres-operator -c operator
```

---

## Exercise 2: Deploying the Database Cluster and Observing Reconciliation

With the controller active, deploying a `PostgresCluster` Custom Resource will trigger the reconciler loop to deploy physical database pods.

### 1. Deploy the Custom Resource
```bash
kubectl apply -f manifests/postgres-cr.yaml
```

### 2. Observe the Reconciliation Cycle
Watch the operator logs stream:
```bash
kubectl logs deployment/postgres-operator -c operator --tail=20
```

*Expected Log Sequence:*
```text
INFO[0001] Event received: ADD PostgresCluster default/prod-db-cluster
INFO[0002] Reconciling PostgresCluster default/prod-db-cluster
INFO[0002] Status: Pending. Provisioning initial workloads...
INFO[0003] Actual replicas (0) != Desired (3). Creating StatefulSet postgres-prod-db-cluster
INFO[0004] Creating Read/Write service prod-db-cluster-primary
INFO[0004] Creating Read-Only service prod-db-cluster-replicas
INFO[0015] PostgresCluster default/prod-db-cluster status updated to Ready
```

### 3. Verify Custom Resource Phase Status
Query the resource again. Notice how the printer columns are now fully populated:
```bash
kubectl get postgresclusters
```

*Expected Output:*
```text
NAME              REPLICAS   READY REPLICAS   VERSION   PHASE   AGE
prod-db-cluster   3          3                15.2      Ready   1m
```

---

## Exercise 3: Scaling the Database Cluster

Because the CRD defines a scale subresource, we can use the native Kubernetes scale commands.

### 1. Execute Scaling Command
Scale the cluster size from 3 to 5:
```bash
kubectl scale --replicas=5 postgrescluster/prod-db-cluster
```

### 2. Observe the Rolling Scale
Check the active database pods being initialized:
```bash
kubectl get pods -l app=postgres-prod-db-cluster -w
```
You will see `postgres-prod-db-cluster-3` and `postgres-prod-db-cluster-4` transition from `Pending` to `ContainerCreating` and finally `Running`.

Verify the status updates in the custom resource:
```bash
kubectl get pgdb prod-db-cluster
```
*Expected Output:*
```text
NAME              REPLICAS   READY REPLICAS   VERSION   PHASE   AGE
prod-db-cluster   5          5                15.2      Ready   3m
```

---

## Exercise 4: Failure Handling & Automated Recovery

Let's test the operator's self-healing capabilities by manually injecting a crash.

### 1. Delete a Database Pod
Delete the primary node pod (`postgres-prod-db-cluster-0`):
```bash
kubectl delete pod postgres-prod-db-cluster-0
```

### 2. Watch Reconciliation Self-Heal
Immediately list the pods:
```bash
kubectl get pods -l app=postgres-prod-db-cluster
```
*Expected Output:*
```text
NAME                         READY   STATUS        RESTARTS   AGE
postgres-prod-db-cluster-0   0/1     Terminating   0          4m
postgres-prod-db-cluster-0   0/1     Pending       0          1s
postgres-prod-db-cluster-0   1/1     Running       0          12s
```
*Explanation:* The Shared Informer detected the deletion event from the API server and enqueued the database key. The reconciliation loop computed that the actual number of pods (4) was less than the desired replicas (5) and automatically regenerated the missing StatefulSet pod.

---

## Exercise 5: Orchestrating an Engine Upgrade

Upgrading databases usually involves database version increments, schema migrations, and rolling out binary binaries without downtime. Our operator manages this via rolling updates of the replica nodes before promotion.

### 1. Modify Database Version Spec
Update the version of the database from `"15.2"` to `"16.0"`. We can do this using a quick patch command:
```bash
kubectl patch postgrescluster prod-db-cluster --type='merge' -p '{"spec":{"version":"16.0"}}'
```

### 2. Monitor Upgrade Sequence
Watch the pods terminate and recreate in reverse order (StatefulSet rolling update):
```bash
kubectl get pods -l app=postgres-prod-db-cluster -w
```
You will notice the operator updates the status to `Upgrading`, then rolls pods starting from index 4 down to 0, ensuring that the primary database is only updated and failed over at the very end.

Verify the version upgrade has succeeded:
```bash
kubectl get pgdb prod-db-cluster
```
*Expected Output:*
```text
NAME              REPLICAS   READY REPLICAS   VERSION   PHASE   AGE
prod-db-cluster   5          5                16.0      Ready   8m
```

---

## Clean Up
Remove the database cluster and the operator deployment from the cluster:
```bash
kubectl delete postgrescluster prod-db-cluster
kubectl delete -f manifests/operator-rbac-deployment.yaml
```
All child pods, services, and configuration mappings will automatically be garbage collected.
