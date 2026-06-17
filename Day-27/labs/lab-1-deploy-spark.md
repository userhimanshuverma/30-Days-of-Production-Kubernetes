# Lab 1: Deploying Apache Spark & Running Jobs on Kubernetes

## Objective
Install the Spark on Kubernetes Operator, configure role-based access control (RBAC), enable executor dynamic allocation, and run a Python SparkPi application.

---

## Step 1: Install Spark on Kubernetes Operator
We will use Helm to install the Spark Operator. This operator introduces custom resource definitions (CRDs) for managing Spark applications as declarative Kubernetes specifications.

```bash
# Add the Helm repository
helm repo add spark-operator https://googlecloudplatform.github.io/spark-on-k8s-operator

# Update charts
helm repo update

# Install the operator in the default namespace (or create a dedicated one)
helm install my-release spark-operator/spark-operator \
  --namespace default \
  --set webhook.enable=true
```

Verify the operator pod is running:
```bash
kubectl get pods -l app.kubernetes.io/name=spark-operator
```
*Expected Output:*
```
NAME                                                 READY   STATUS    RESTARTS   AGE
my-release-spark-operator-8d6c74bf5-abcde             1/1     Running   0          45s
```

---

## Step 2: Configure RBAC Permissions
Before running a Spark application, we must create a ServiceAccount, Role, and RoleBinding. The Spark Driver pod uses these credentials to dynamically create and delete executor pods.

Apply the RBAC manifest:
```bash
kubectl apply -f manifests/spark-operator-rbac.yaml
```
*Expected Output:*
```
serviceaccount/spark-serviceaccount created
role.rbac.authorization.k8s.io/spark-role created
rolebinding.rbac.authorization.k8s.io/spark-rolebinding created
```

---

## Step 3: Run the Spark Application with Dynamic Allocation
We will run a PySpark job that estimates Pi using Monte Carlo methods. We will utilize **Dynamic Allocation**, meaning Spark will spawn executor pods when calculation starts and terminate them when idle.

Inspect the manifest at [manifests/spark-pi-app.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-27/manifests/spark-pi-app.yaml) and apply it:
```bash
kubectl apply -f manifests/spark-pi-app.yaml
```
*Expected Output:*
```
sparkapplication.sparkoperator.k8s.io/spark-pi-dynamic created
```

---

## Step 4: Monitor Pod Creation and Execution
Watch the pods in your namespace:
```bash
kubectl get pods -w -l 'sparkoperator.k8s.io/app-name=spark-pi-dynamic'
```
*Expected Execution Flow:*
1. **Driver Spawn**: `spark-pi-dynamic-driver` starts up in `Pending` -> `ContainerCreating` -> `Running`.
2. **Executor Requests**: The driver contacts the API server and launches executor pods: `spark-pi-dynamic-exec-1` and `spark-pi-dynamic-exec-2`.
3. **Execution**: Executors change state to `Running` and pull tasks from the driver.
4. **Shutdown**: Once the computation completes, the executor pods are reaped. The driver pod remains in `Completed` state.

```
NAME                          READY   STATUS             RESTARTS   AGE
spark-pi-dynamic-driver       1/1     Running            0          12s
spark-pi-dynamic-exec-1       1/1     Running            0          4s
spark-pi-dynamic-exec-2       1/1     Running            0          4s
spark-pi-dynamic-exec-1       0/1     Completed          0          28s
spark-pi-dynamic-exec-2       0/1     Completed          0          28s
spark-pi-dynamic-driver       0/1     Completed          0          35s
```

---

## Step 5: Read Spark Logs
Inspect the output logs of the Driver pod to verify execution success:
```bash
kubectl logs spark-pi-dynamic-driver
```
*Expected Output:*
```
...
Starting Spark Pi computation with 100 partitions...
Total samples to execute: 10000000
...
-------------------------------------------------------------------
Pi is roughly 3.1415926
-------------------------------------------------------------------
...
```

To clean up the completed job:
```bash
kubectl delete sparkapplication spark-pi-dynamic
```
