# Day 30 — Master Project Guide: 12 Hands-on Labs

This guide provides the complete step-by-step instructions for implementing, deploying, scaling, observing, and operating the Production-Ready Kubernetes platform.

---

## 🛠️ Lab 1: Build Kubernetes Cluster

### Objective
Create a multi-node High-Availability (HA) Kubernetes cluster locally using Kind, configuring multiple control plane nodes and worker nodes with a shared ingress proxy.

### Step 1: Examine the cluster configuration file
Navigate to `02-cluster/kind-ha-config.yaml` to view the multi-node configuration. This creates 3 control plane nodes (to replicate a production etcd/control plane cluster) and 3 worker nodes.

### Step 2: Deploy the cluster
Run the setup script:
```bash
chmod +x 02-cluster/setup-cluster.sh
./02-cluster/setup-cluster.sh
```

### Verification
Verify that all 6 nodes are running and ready:
```bash
kubectl get nodes -o wide
```
Ensure that the 3 control plane nodes have the control-plane role, and that CoreDNS is functioning properly:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

---

## 🛠️ Lab 2: Deploy Ingress & TLS

### Objective
Configure external request routing into the cluster with an NGINX Ingress controller and set up TLS encryption via cert-manager.

### Step 1: Install the NGINX Ingress Controller
Apply the ingress controller manifests:
```bash
kubectl apply -f 03-networking/ingress-nginx.yaml
```
Wait until the ingress controller pod is fully running:
```bash
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s
```

### Step 2: Install cert-manager
Deploy cert-manager CRDs and configurations to handle certificate lifecycles automatically:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml
```
Wait for cert-manager deployments to complete:
```bash
kubectl wait --namespace cert-manager \
  --for=condition=available deployment \
  --all \
  --timeout=90s
```

### Step 3: Apply the ClusterIssuer
Deploy the Let's Encrypt Staging ClusterIssuer:
```bash
kubectl apply -f 03-networking/cert-manager-issuer.yaml
```

### Verification
Inspect the ClusterIssuer state:
```bash
kubectl get clusterissuer letsencrypt-staging
```

---

## 🛠️ Lab 3: Deploy Monitoring Stack

### Objective
Install and configure the Prometheus Operator and Grafana for monitoring cluster and container metrics.

### Step 1: Deploy Prometheus Operator and Core Metrics
Apply the Prometheus stack configurations:
```bash
kubectl apply -f https://github.com/prometheus-operator/kube-prometheus/raw/main/manifests/setup/prometheus-operator-deployment.yaml
# Deploy Prometheus rules, alerting, and Grafana presets:
kubectl apply -f 05-monitoring/prometheus-rules.yaml
```

### Step 2: Apply the Custom Grafana Dashboard Config
Load the pre-configured platform dashboard config into your cluster:
```bash
kubectl create configmap platform-grafana-dashboard --from-file=05-monitoring/grafana-dashboard.json -n monitoring
```

### Verification
Verify the Prometheus and Grafana pods are running:
```bash
kubectl get pods -n monitoring
```

---

## 🛠️ Lab 4: Deploy Logging Stack

### Objective
Install Grafana Loki for log aggregation and Promtail as the logging daemon to aggregate all container logs from `/var/log/pods/`.

### Step 1: Deploy Loki and Promtail
Apply the aggregated logging manifest:
```bash
kubectl apply -f 10-observability/loki-promtail.yaml
```

### Verification
Confirm that the Loki StatefulSet and the Promtail DaemonSet are active:
```bash
kubectl get daemonset promtail -n observability
kubectl get statefulset loki -n observability
```
Verify logs are streaming by checking Promtail console output:
```bash
kubectl logs -n observability -l app=promtail --tail=20
```

---

## 🛠️ Lab 5: Deploy CI/CD GitOps Layer

### Objective
Deploy ArgoCD to govern the GitOps reconciliation loop, synchronizing the repo manifests into the cluster.

### Step 1: Deploy ArgoCD
Create the namespace and install the controller:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Step 2: Apply the GitOps Application Spec
Deploy the Master GitOps application file:
```bash
kubectl apply -f 06-cicd/argo-app.yaml
```

### Verification
Check the sync status of the GitOps applications:
```bash
kubectl get apps -n argocd
```

---

## 🛠️ Lab 6: Deploy Stateful Services

### Objective
Deploy a highly available PostgreSQL cluster using CloudNativePG and a Kafka streaming broker system using Strimzi.

### Step 1: Deploy PostgreSQL HA Database
Apply the Postgres cluster configuration:
```bash
kubectl apply -f 08-stateful-workloads/postgres-ha.yaml
```
Verify the cluster status:
```bash
kubectl get pods -l cnpg.io/cluster=postgres-ha -w
```

### Step 2: Deploy Kafka Stream Brokers
Apply the Kafka Strimzi manifests:
```bash
kubectl apply -f 08-stateful-workloads/kafka-strimzi.yaml
```

### Verification
Check that both stateful sets have generated their respective pods and bound their PVCs:
```bash
kubectl get pvc
kubectl get pods -l app.kubernetes.io/name=kafka
```

---

## 🛠️ Lab 7: Deploy AI/Data Service

### Objective
Deploy the FastAPI AI inference microservice that connects to both Postgres (saving logs) and Kafka (publishing prediction events).

### Step 1: Build the Application Container (Conceptual)
Check the `09-ai-data-services/fastapi-app/Dockerfile` to see the multi-stage build.

### Step 2: Deploy the App Manifests
Apply the Deployment, Ingress rules, and ClusterIP:
```bash
kubectl apply -f 09-ai-data-services/k8s-deployment.yaml
```

### Verification
Check deployment status:
```bash
kubectl rollout status deployment/fastapi-ai-service
```
Run a port-forward and test the service:
```bash
kubectl port-forward svc/fastapi-ai-service 8080:80 &
curl -X POST http://localhost:8080/predict -H "Content-Type: application/json" -d '{"data": [1.0, 2.0, 3.0]}'
kill %1
```

---

## 🛠️ Lab 8: Configure Autoscaling

### Objective
Establish dual-layer autoscaling: workload autoscaling via HPA/VPA and compute autoscaling via Karpenter.

### Step 1: Deploy HPA & VPA Specs
```bash
kubectl apply -f 07-autoscaling/hpa-vpa.yaml
```

### Step 2: Deploy Karpenter NodePool definitions
Apply the Karpenter configuration for node provisioning:
```bash
kubectl apply -f 07-autoscaling/karpenter-nodepool.yaml
```

### Verification
Query the horizontal scaler status:
```bash
kubectl get hpa
kubectl get vpa
```

---

## 🛠️ Lab 9: Configure Security

### Objective
Establish secure namespace isolation using Calico Network Policies, assign Least-Privilege RBAC scopes, and load secrets from Vault.

### Step 1: Apply RBAC Rules
```bash
kubectl apply -f 04-security/rbac-roles.yaml
```

### Step 2: Apply Network Policies
```bash
kubectl apply -f 04-security/network-policies.yaml
```

### Step 3: Configure External Secrets Mapping
```bash
kubectl apply -f 04-security/secrets-vault.yaml
```

### Verification
Run a verification command to check blocked traffic:
```bash
kubectl run test-pod --rm -i --tty --image=alpine -- sh
# Inside the container, try checking PostgreSQL connectivity:
nc -zvw3 postgres-ha-rw 5432
# It should time out due to the isolation network policies.
```

---

## 🛠️ Lab 10: Disaster Recovery Drill

### Objective
Execute a multi-region failover dry-run by backing up databases with Velero and shifting ingress DNS traffic rules.

### Step 1: Execute a backup
Run a Velero backup:
```bash
kubectl apply -f 12-operations/velero-backup.yaml
```

### Step 2: Perform DB Failover
Execute the instructions in `12-operations/dr-failover-runbook.md` to trigger replication promotion in the standby site.

### Verification
Verify Postgres master switch in standby logs:
```bash
kubectl logs -l cnpg.io/cluster=postgres-ha -c manager --tail=100
```

---

## 🛠️ Lab 11: Run Production Load Test

### Objective
Stress-test the FastAPI AI endpoint using k6 to evaluate container load behavior and trigger HPA scaling.

### Step 1: Install k6
Follow standard installation rules for your OS to run k6.

### Step 2: Execute load test script
Run the k6 test script pointing to the app's endpoint:
```bash
k6 run 11-testing/k6-load-test.js
```

### Verification
Watch replicas scale up during the load test:
```bash
kubectl get hpa fastapi-ai-service --watch
```

---

## 🛠️ Lab 12: Operate Platform During Failure

### Objective
Inject a failure state (e.g. database password corrupt, high CPU load, or network drop) and observe recovery.

### Step 1: Run diagnostic script
Examine the script `13-troubleshooting/diagnose-platform.sh` to check system health.

### Step 2: Diagnose the failure
Execute the diagnosis tool to analyze current cluster logs and detect anomalies:
```bash
chmod +x 13-troubleshooting/diagnose-platform.sh
./13-troubleshooting/diagnose-platform.sh
```
Identify and fix the issue according to the playbook inside `13-troubleshooting/scenarios.md`.
