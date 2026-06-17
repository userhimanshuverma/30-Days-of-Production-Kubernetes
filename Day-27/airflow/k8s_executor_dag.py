from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from kubernetes.client import models as k8s

# Default arguments for the workflow
default_args = {
    'owner': 'platform-engineering',
    'depends_on_past': False,
    'start_date': datetime(2026, 6, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

# Define the production DAG
with DAG(
    'k8s_executor_etl_pipeline',
    default_args=default_args,
    description='A production ETL pipeline demonstrating KubernetesExecutor and KubernetesPodOperator capabilities',
    schedule_interval='@daily',
    catchup=False,
    tags=['production', 'analytics', 'k8s'],
) as dag:

    # Task 1: Lightweight Bash task. 
    # Because we are using the KubernetesExecutor, the Scheduler will automatically
    # spawn a clean, isolated worker pod for this task. Once execution ends, the pod is reaped.
    extract_metadata = BashOperator(
        task_id='extract_raw_metadata',
        bash_command='echo "Extracting telemetry metadata..." && sleep 10',
    )

    # Task 2: Heavyweight Data Transformation.
    # We use the KubernetesPodOperator to gain absolute control over the execution pod's environment.
    # This allows mounting volumes, setting distinct resource requests/limits, tolerating taints, and specifying images.
    
    # Define CPU and Memory Requests and Limits for the Task Pod
    task_resources = k8s.V1ResourceRequirements(
        requests={'cpu': '2000m', 'memory': '4Gi'},
        limits={'cpu': '4000m', 'memory': '8Gi'}
    )

    # Define Node Affinity (Schedule only on the specialized "analytics-optimized" node pool)
    task_affinity = k8s.V1Affinity(
        node_affinity=k8s.V1NodeAffinity(
            required_during_scheduling_ignored_during_execution=k8s.V1NodeSelector(
                node_selector_terms=[
                    k8s.V1NodeSelectorTerm(
                        match_expressions=[
                            k8s.V1NodeSelectorRequirement(
                                key='instance-type',
                                operator='In',
                                values=['analytics-optimized']
                            )
                        ]
                    )
                ]
            )
        )
    )

    # Define Toleration (Allow running on tainted spot instances to optimize cost)
    task_tolerations = [
        k8s.V1Toleration(
            key='spot',
            operator='Equal',
            value='true',
            effect='NoSchedule'
        )
    ]

    transform_telemetry = KubernetesPodOperator(
        namespace='default',
        image='python:3.9-slim',
        cmds=['python', '-c'],
        arguments=['print("Processing heavy telemetry events..."); import time; time.sleep(30); print("Completed processing!")'],
        labels={'app': 'airflow-transformer', 'tier': 'etl'},
        name='airflow-telemetry-transformer',
        task_id='heavyweight_transform',
        get_logs=True,
        resources=task_resources,
        affinity=task_affinity,
        tolerations=task_tolerations,
        # env_vars={
        #     'DB_HOST': 'airflow-postgres',
        #     'DB_USER': 'airflow'
        # },
        is_delete_operator_pod=True, # Automatically clean up the pod on completion to avoid resource cluttering
    )

    # Task 3: Load and notify.
    load_to_olap = BashOperator(
        task_id='trigger_pinot_refresh',
        bash_command='echo "Notifying Pinot Controller of offline segments available..." && sleep 5',
    )

    # Define task execution order
    extract_metadata >> transform_telemetry >> load_to_olap
