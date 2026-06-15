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
        "readyReplicas": replicas,
        "selector": f"app=postgres-{name}"
    }

@kopf.on.delete('database.production.k8s', 'v1alpha1', 'postgresclusters')
def delete_postgres(name, namespace, logger, **kwargs):
    logger.info(f"Custom Resource PostgresCluster {namespace}/{name} deleted. Clean-up sequence complete.")
