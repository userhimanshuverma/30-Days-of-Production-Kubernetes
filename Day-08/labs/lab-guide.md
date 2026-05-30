# 🛠️ Day 08 Labs — Hands-On Storage Guides

This guide contains 5 hands-on labs to configure, run, and scale persistent storage in a local development cluster (Kind/Minikube) or a production cloud cluster.

---

## Lab 1: Manual PV-PVC Static Binding

In this lab, we will simulate a local node mount by manually provisioning a `PersistentVolume` (PV) and binding a `PersistentVolumeClaim` (PVC) to it.

### Step 1: Create a Local Directory on the Node
If you are using **Kind**, you must create the target mount directory inside the Kind control-plane container:
```bash
docker exec -it kind-control-plane mkdir -p /mnt/disks/ssd1
```

### Step 2: Apply the Local PV Manifest
Apply the static volume mapping definition [01-local-pv.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-08/manifests/01-local-pv.yaml):
```bash
kubectl apply -f manifests/01-local-pv.yaml
```

Verify that the PV is created successfully:
```bash
kubectl get pv
```
**Expected Output**:
```
NAME             CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS    REASON   AGE
local-pv-day08   10Gi       RWO            Retain           Available           local-storage            10s
```
*Note that the status is `Available`, meaning it is ready to be claimed.*

### Step 3: Apply the Local PVC Manifest
Apply the claim [02-local-pvc.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-08/manifests/02-local-pvc.yaml):
```bash
kubectl apply -f manifests/02-local-pvc.yaml
```

Verify the binding status:
```bash
kubectl get pvc
```
**Expected Output**:
```
NAME              STATUS   VOLUME           CAPACITY   ACCESS MODES   STORAGECLASS    AGE
local-pvc-day08   Bound    local-pv-day08   10Gi       RWO            local-storage   5s
```
*The status changes to `Bound`, indicating K8s successfully linked the claim to the PV.*

---

## Lab 2: Dynamic Provisioning with StorageClasses

Dynamic provisioning allows the cluster to coordinate directly with the cloud APIs to generate disks on-demand.

### Step 1: Deploy a StorageClass
Deploy the `gp3` StorageClass manifest [03-sc-gp3.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-08/manifests/03-sc-gp3.yaml):
```bash
kubectl apply -f manifests/03-sc-gp3.yaml
```

Verify the StorageClass details:
```bash
kubectl get sc
```
**Expected Output**:
```
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
gp3             ebs.csi.aws.com         Delete          WaitForFirstConsumer   true                   5s
local-storage   kubernetes.io/no-provisioner Delete     Immediate              false                  2m
```

### Step 2: Apply the Dynamic Claim
Create the PVC requesting a `gp3` volume [05-dynamic-pvc.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-08/manifests/05-dynamic-pvc.yaml):
```bash
kubectl apply -f manifests/05-dynamic-pvc.yaml
```

Verify the PVC state:
```bash
kubectl get pvc dynamic-pvc-day08
```
**Expected Output**:
```
NAME                STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
dynamic-pvc-day08   Pending                                      gp3            4s
```
> [!NOTE]
> Why is it stuck in `Pending`?
> Because the `gp3` StorageClass is configured with `volumeBindingMode: WaitForFirstConsumer`. It will remain Pending until a Pod is scheduled that mounts this PVC.

---

## Lab 3: Deploying a Persistent Database StatefulSet

We will deploy a PostgreSQL cluster using a StatefulSet. The database replicas will automatically provision individual PVs from the StorageClass.

### Step 1: Deploy the StatefulSet [06-postgres-statefulset.yaml](file:///d:/30_Days_of_Production_Kubernetes/Day-08/manifests/06-postgres-statefulset.yaml)
```bash
kubectl apply -f manifests/06-postgres-statefulset.yaml
```

### Step 2: Monitor Pods and Claims Creation
Watch the resources spawn:
```bash
kubectl get pods -w
```
You will observe:
1. `postgres-db-0` starts scheduling.
2. The dynamic provisioner creates a cloud disk for `pg-data-postgres-db-0` and mounts it.
3. `postgres-db-0` moves to `Running`.
4. `postgres-db-1` starts scheduling, provisions a second separate disk `pg-data-postgres-db-1`, and moves to `Running`.

Verify the generated claims:
```bash
kubectl get pvc
```
**Expected Output**:
```
NAME                      STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
pg-data-postgres-db-0     Bound    pvc-87ea3140-5e8a-4933-bfbd-ef171887e500   10Gi       RWO            gp3            45s
pg-data-postgres-db-1     Bound    pvc-a083f2a8-12cd-4da1-965a-fa1284d720b0   10Gi       RWO            gp3            30s
```

---

## Lab 4: Simulating Pod Restarts and Verifying Persistence

This lab visually proves that even if a Pod is destroyed, its disk volume is reattached with all database tables intact.

### Step 1: Write Data to the Database
Expose the database or exec directly into `postgres-db-0` to populate a table:
```bash
kubectl exec -it postgres-db-0 -- psql -U pg_admin -d prod_db -c "CREATE TABLE test_table (id SERIAL PRIMARY KEY, val VARCHAR(50));"
kubectl exec -it postgres-db-0 -- psql -U pg_admin -d prod_db -c "INSERT INTO test_table (val) VALUES ('Kubernetes storage rocks!');"
```

Verify that the row was written:
```bash
kubectl exec -it postgres-db-0 -- psql -U pg_admin -d prod_db -c "SELECT * FROM test_table;"
```

### Step 2: Delete the Pod
Simulate a node failure or crash by deleting the Pod:
```bash
kubectl delete pod postgres-db-0
```

### Step 3: Verify the Data after Rescheduling
Wait for the Pod to restart and become healthy:
```bash
kubectl wait --for=condition=Ready pod/postgres-db-0 --timeout=60s
```

Query the database table inside the newly created pod:
```bash
kubectl exec -it postgres-db-0 -- psql -U pg_admin -d prod_db -c "SELECT * FROM test_table;"
```
**Expected Output**:
```
 id |            val            
----+---------------------------
  1 | Kubernetes storage rocks!
(1 row)
```
*Success! The new Pod automatically mounted the same PV and recovered the state.*

---

## Lab 5: Live Volume Expansion (Resizing)

In this lab, we will expand our database storage space from 10Gi to 15Gi dynamically.

### Step 1: Edit the Claim
Modify the capacity setting directly on the running PVC:
```bash
kubectl patch pvc pg-data-postgres-db-0 -p '{"spec":{"resources":{"requests":{"storage":"15Gi"}}}}'
```

### Step 2: Verify Status Transitions
Check the PVC details:
```bash
kubectl get pvc pg-data-postgres-db-0
```
It will display the updated capacity as `15Gi`.
Check events to verify CSI expansion:
```bash
kubectl describe pvc pg-data-postgres-db-0
```
You will see messages showing:
1. `VolumeExpansionInProgress` (Calling controller-expand on cloud provider).
2. `FileSystemResizeRequired` (Resizing filesystem on the host node).
3. `VolumeResizeSuccessful`.
