# 🛠️ Lab 2: Building a Simple Custom Controller

## Overview
A Custom Resource Definition (CRD) only stores metadata in etcd. To make things happen, you need a **Custom Controller** to act on those specifications. In this lab, you will write a functional controller in Python using the **Kopf** (Kubernetes Operator Framework) library. The controller will watch for `PostgresCluster` resources and automatically reconcile a matching StatefulSet to ensure the database pods are run.

---

## Prerequisites
- A running Kubernetes cluster (Kind, Minikube, etc.)
- Python 3.8+ installed locally
- Access to terminal

---

## Exercise 1: Project Setup

Create a scratch directory inside your workspace and install dependencies:
```bash
# Install Kopf and Kubernetes official python client
pip install kopf kubernetes
```

---

## Exercise 2: Writing the Controller Code

Create a file named [operator.py](file:///d:/30_Days_of_Production_Kubernetes/Day-24/operators/operator.py) (we will write this code file under the `operators/` folder).

This script performs the following logic:
1. Registers a watch on `postgresclusters` in the `database.production.k8s` group.
2. When a custom resource is created or updated, it extracts `replicas`, `version`, and `storage` specs.
3. Compares actual state by looking for a StatefulSet matching the database cluster name.
4. Generates or updates the StatefulSet to match desired specs.
5. Emits events and writes the state status (e.g., `phase = Ready`) back to the custom resource status subresource.

### Let's write the code block:

```python
import os
import kopf
import kubernetes.client as k8s
from kubernetes.client.rest import ApiException

@kopf.on.create('database.production.k8s', 'v1alpha1', 'postgresclusters')
@kopf.on.update('database.production.k8s', 'v1alpha1', 'postgresclusters')
def reconcile_postgres(spec, name, namespace, logger, **kwargs):
    # 1. Fetch Desired Configurations from Spec
    replicas = spec.get('replicas', 3)
    version = spec.get('version', '15.2')
    storage_size = spec.get('storage', {}).get('size', '10Gi')
    storage_class = spec.get('storage', {}).get('class', 'standard')
    
    logger.info(f"Reconciling PostgresCluster {namespace}/{name}: Replicas={replicas}, Version={version}")
    
    # Initialize Core V1 & Apps V1 API Clients
    apps_api = k8s.AppsV1Api()
    
    # 2. Define Desired StatefulSet Structure
    statefulset_manifest = {
        "apiVersion": "apps/v1",
        "kind": "StatefulSet",
        "metadata": {
            "name": f"postgres-{name}",
            "namespace": namespace
        },
        "spec": {
            "replicas": replicas,
            "serviceName": f"postgres-{name}-svc",
            "selector": {
                "matchLabels": {"app": f"postgres-{name}"}
            },
            "template": {
                "metadata": {
                    "labels": {"app": f"postgres-{name}"}
                },
                "spec": {
                    "containers": [
                        {
                            "name": "postgres",
                            "image": f"postgres:{version}-alpine",
                            "env": [
                                {"name": "POSTGRES_HOST_AUTH_METHOD", "value": "trust"}
                            ],
                            "ports": [{"containerPort": 5432, "name": "postgres"}],
                            "volumeMounts": [{"name": "pgdata", "mountPath": "/var/lib/postgresql/data"}]
                        }
                    ]
                }
            },
            "volumeClaimTemplates": [
                {
                    "metadata": {"name": "pgdata"},
                    "spec": {
                        "accessModes": ["ReadWriteOnce"],
                        "storageClassName": storage_class,
                        "resources": {"requests": {"storage": storage_size}}
                    }
                }
            ]
        }
    }
    
    # Adopt object for Owner References inside Kopf framework
    kopf.adopt(statefulset_manifest)
    
    # 3. Read Actual State and Compare/Act
    try:
        # Check if StatefulSet already exists
        sts = apps_api.read_namespaced_stateful_set(name=f"postgres-{name}", namespace=namespace)
        logger.info(f"StatefulSet postgres-{name} exists. Reconciling spec differentials.")
        
        # Update spec fields if drift is found (Scale or Version Upgrade)
        if sts.spec.replicas != replicas or sts.spec.template.spec.containers[0].image != f"postgres:{version}-alpine":
            apps_api.patch_namespaced_stateful_set(
                name=f"postgres-{name}",
                namespace=namespace,
                body=statefulset_manifest
            )
            logger.info("Successfully patched StatefulSet properties to match Custom Resource spec.")
            
    except ApiException as e:
        if e.status == 404:
            # Create StatefulSet if not exists
            logger.info(f"StatefulSet postgres-{name} not found. Provisioning new workload.")
            apps_api.create_namespaced_stateful_set(namespace=namespace, body=statefulset_manifest)
        else:
            raise kopf.TemporaryError(f"API communication failure: {e}")

    # 4. Update Custom Resource Status Subresource
    return {
        "phase": "Ready",
        "replicas": replicas,
        "readyReplicas": replicas, # Real controller would check sts.status.ready_replicas
        "selector": f"app=postgres-{name}"
    }

@kopf.on.delete('database.production.k8s', 'v1alpha1', 'postgresclusters')
def delete_postgres(name, namespace, logger, **kwargs):
    logger.info(f"Custom Resource PostgresCluster {namespace}/{name} deleted. Clean-up sequence complete.")
```

Let's write this code file to the operator path `d:\30_Days_of_Production_Kubernetes\Day-24\operators\operator.py`. (I will call `write_to_file` in a separate step).

---

## Exercise 3: Running the Controller

### 1. Launch the Controller Locally
Run Kopf in dev mode. It will automatically load credentials from your local `~/.kube/config` context:
```bash
kopf run operators/operator.py --verbose
```

*Expected Terminal Log Output:*
```text
[INFO    ] Kopf is startup-ready.
[INFO    ] Watching API database.production.k8s/v1alpha1 for postgresclusters
```

### 2. Apply Custom Resource
In another terminal, apply your custom resource:
```bash
kubectl apply -f manifests/postgres-cr.yaml
```

Watch the controller logs! You will see:
```text
[INFO    ] Reconciling PostgresCluster default/prod-db-cluster: Replicas=3, Version=15.2
[INFO    ] StatefulSet postgres-prod-db-cluster not found. Provisioning new workload.
[INFO    ] Handler 'reconcile_postgres' succeeded.
```

### 3. Verify Created Workloads
Check if the controller created the matching statefulset and database pods:
```bash
kubectl get statefulsets,pods
```

*Expected Output:*
```text
NAME                                         READY   AGE
statefulset.apps/postgres-prod-db-cluster    3/3     45s

NAME                              READY   STATUS    RESTARTS   AGE
pod/postgres-prod-db-cluster-0    1/1     Running   0          45s
pod/postgres-prod-db-cluster-1    1/1     Running   0          35s
pod/postgres-prod-db-cluster-2    1/1     Running   0          25s
```

### 4. Verify Owner Reference and Garbage Collection
Verify that deleting the `PostgresCluster` automatically deletes the child resources due to the `ownerReferences` configured by the controller:
```bash
kubectl delete postgrescluster prod-db-cluster
```

Observe your controller terminal logs:
```text
[INFO    ] Custom Resource PostgresCluster default/prod-db-cluster deleted. Clean-up sequence complete.
```

Verify that the StatefulSet was cleaned up:
```bash
kubectl get statefulset postgres-prod-db-cluster
```
*Expected Output:*
```text
Error from server (NotFound): statefulsets.apps "postgres-prod-db-cluster" not found
```
This demonstrates how owners cascading deletes clean up auxiliary infrastructure automatically.
