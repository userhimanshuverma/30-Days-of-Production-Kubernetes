# Lab 2: Deploying Apache Airflow with KubernetesExecutor

## Objective
Set up a PostgreSQL metadata database using a StatefulSet, configure the Airflow webserver and scheduler to use the `KubernetesExecutor`, and run tasks that dynamically spawn worker pods.

---

## Step 1: Deploy PostgreSQL Metadata Database
Airflow requires a relational database to maintain state. We use a **StatefulSet** with a persistent volume to ensure that the database state survives container restarts.

Apply the Postgres manifest:
```bash
kubectl apply -f manifests/airflow-db-statefulset.yaml
```
Verify the storage binding and pod status:
```bash
kubectl get pvc
kubectl get pods -l app=airflow-postgres
```
*Expected Output:*
```
NAME                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
postgres-db-volume-airflow-postgres-0 Bound    pvc-1234abcd-5678-efgh-ijkl-90abcdef1234   20Gi       RWO            local-nvme     45s

NAME                 READY   STATUS    RESTARTS   AGE
airflow-postgres-0   1/1     Running   0          45s
```

---

## Step 2: Set Up Airflow Core Configuration & RBAC
For the Airflow Scheduler to spawn task worker pods on-demand, it must possess RBAC permissions to `create`, `list`, `watch`, and `delete` pods in its namespace.

Inspect the config map and RBAC setup in [manifests/airflow-k8s-executor.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-27/manifests/airflow-k8s-executor.yaml). Note the core config:
* `AIRFLOW__CORE__EXECUTOR`: Set to `KubernetesExecutor`.
* `AIRFLOW__CORE__SQL_ALCHEMY_CONN`: Pointed to the PostgreSQL StatefulSet internal service.

Apply the configurations:
```bash
kubectl apply -f manifests/airflow-k8s-executor.yaml
```
*Expected Output:*
```
configmap/airflow-config created
serviceaccount/airflow-scheduler-sa created
role.rbac.authorization.k8s.io/airflow-scheduler-role created
rolebinding.rbac.authorization.k8s.io/airflow-scheduler-rolebinding created
service/airflow-webserver created
deployment.apps/airflow-webserver created
deployment.apps/airflow-scheduler created
```

Verify that both the webserver and scheduler pods are running:
```bash
kubectl get pods -l component=webserver
kubectl get pods -l component=scheduler
```

---

## Step 3: Trigger a DAG and Watch Worker Pods
When a DAG runs, the Scheduler parses the tasks and calls the Kubernetes API to launch an individual worker pod for each task.

1. Port-forward the Web UI to access the dashboard on your local machine:
   ```bash
   kubectl port-forward svc/airflow-webserver 8080:8080
   ```
2. Open your browser and navigate to `http://localhost:8080`.
3. In the UI, locate the DAG named `k8s_executor_etl_pipeline`. (If you copied the DAG script into the DAG folder, it will appear).
4. Unpause the DAG and trigger it.
5. In another terminal window, watch the pods in real-time:
   ```bash
   kubectl get pods -w
   ```
   *Expected Execution Loop:*
   ```
   NAME                                                READY   STATUS              RESTARTS   AGE
   airflow-scheduler-7b56d8f89-abcde                   1/1     Running             0          2m
   airflow-webserver-5fd9b8c67-12345                   1/1     Running             0          2m
   k8sexecutoretlpipeline-extractrawmetadata-a1b2c3d4  0/1     Pending             0          1s
   k8sexecutoretlpipeline-extractrawmetadata-a1b2c3d4  0/1     ContainerCreating   0          2s
   k8sexecutoretlpipeline-extractrawmetadata-a1b2c3d4  1/1     Running             0          4s
   k8sexecutoretlpipeline-extractrawmetadata-a1b2c3d4  0/1     Completed           0          14s
   ```

Observe that the worker pod starts, executes the Bash task, and is deleted automatically.
If you check the logs of the scheduler, you will see the pod orchestration calls:
```bash
kubectl logs deployment/airflow-scheduler -c scheduler | grep -i "pod"
```
