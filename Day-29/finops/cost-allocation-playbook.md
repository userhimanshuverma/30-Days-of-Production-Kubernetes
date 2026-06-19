# 💸 Kubernetes Cost Allocation & Visibility Playbook

This playbook establishes the framework for allocating, tracking, and optimizing Kubernetes costs across multi-tenant clusters. It details how to distribute raw cloud infrastructure costs (EC2, EBS, Network, Load Balancer) to engineering teams, products, and cost centers.

---

## 1. The Cost Allocation Challenge in Kubernetes

Unlike traditional cloud infrastructure where one VM equals one cost-center tag, Kubernetes is a **shared multi-tenant pool**. A single underlying VM (Node) runs pods belonging to different teams, workloads, and projects simultaneously. 

Without proper Kubernetes-native FinOps, cloud bills simply show massive instance costs under a general "Kubernetes Cluster Node Pool" tag, creating an operational visibility black hole.

```
[Raw AWS/GCP Bill] ──> "k8s-nodes-asg" ($150,000/mo)
                                 │
                   ┌─────────────┼─────────────┐
                   ▼             ▼             ▼
              [Team Alpha]  [Team Beta]   [Shared Services]
              (How much?)   (How much?)    (Ingress, DNS...)
```

---

## 2. Enterprise Tagging & Labeling Standards

Cost allocation begins with a mandatory labeling schema applied to every Namespace and Pod.

### Mandatory Metadata Labels
Every namespace MUST be labeled with the following keys:

| Label Key | Purpose | Example Value |
|---|---|---|
| `finops.company.com/cost-center` | Financial accounting ledger code | `cc-9092-marketing` |
| `finops.company.com/owner` | The team accountable for the workloads | `growth-engineering` |
| `finops.company.com/tier` | SLA priority of workloads (Tier-1 to Tier-4) | `tier-2` |
| `finops.company.com/environment` | Environment boundary | `production` |
| `finops.company.com/product` | Revenue-generating product name | `customer-checkout` |

### Enforcing Label Compliance
Ensure workloads cannot be deployed without cost ownership metadata using **Kyverno** or **OPA Gatekeeper**. Below is an example Kyverno policy enforcing cost labels:

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-cost-center
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-namespace-labels
    match:
      any:
      - resources:
          kinds:
          - Namespace
    validate:
      message: "Namespaces must have 'finops.company.com/cost-center' and 'finops.company.com/owner' labels."
      pattern:
        metadata:
          labels:
            finops.company.com/cost-center: "?*"
            finops.company.com/owner: "?*"
```

---

## 3. Allocation Methodology (Showback vs. Chargeback)

| Concept | Action | Audience | Goal |
|---|---|---|---|
| **Showback** | Reports costs to teams without transferring funds. | Engineering Leads & Product Owners | Drive awareness of cost impact. |
| **Chargeback** | Deducts the cost directly from the department's budget. | CFO, Finance, and VP of Engineering | True cost accountability and margin calculation. |

### Allocating Idle & Shared Resources
A major point of friction in chargeback models is **Shared Costs** (e.g., Kube-System, Prometheus, Ingress, Istio Service Mesh, and Node Idle Capacity).

#### Shared System Cost Allocation Strategies:
1. **Flat Rate**: Shared system costs are split equally across all tenant namespaces (e.g., if shared is $5k/mo and there are 5 teams, each pays $1k).
2. **Pro-Rata Allocation (Recommended)**: Distribute shared costs based on the team's proportional usage of the cluster. If Team A consumes 40% of the allocated user space, they pay 40% of the shared system space and idle capacity.
3. **Infrastructure Tax**: A 10% platform tax is added to each team's calculated cost to pay for control-plane and telemetry systems.

---

## 4. Setting Budgets and Anomaly Detection

1. **Static Budgets**: Set namespace cost budgets using tools like Kubecost or OpenCost.
2. **Cost Anomaly Detection**:
   - Establish alerts on sudden spikes in daily spend (e.g., daily namespace cost increases by >25%).
   - Configure Kubecost webhook integration to send alerts to Slack:
   ```json
   {
     "channel": "#finops-alerts",
     "text": "🚨 *Kubernetes Cost Anomaly Detected*!\nNamespace: `ad-campaign-prod`\nDaily Spend Spike: *+45%* ($180 -> $261/day)\nTriggered by: Karpenter scale-up of instance type `m5.8xlarge` due to sudden HPA replica scaling."
   }
   ```
