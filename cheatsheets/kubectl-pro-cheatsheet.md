# Kubectl Pro Cheat Sheet: Advanced Commands & JSONPath

A curated collection of advanced `kubectl` commands and JSONPath output formats for SREs and Platform Engineers.

---

## 🔍 Advanced JSONPath Formats

*   **List Pod Name, Node Name, and Host IP**:
    ```bash
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\t"}{.status.hostIP}{"\n"}{end}'
    ```
*   **Identify Image Tags for All Running Containers**:
    ```bash
    kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}'
    ```
*   **Get Raw Decoded Secret Values (e.g., database password)**:
    ```bash
    kubectl get secret database-secrets -n ai-services -o jsonpath='{.data.password}' | base64 --decode
    ```
*   **Sort Pods by Restart Count**:
    ```bash
    kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'
    ```
*   **Find Pods Failing Readiness Checks**:
    ```bash
    kubectl get pods -A -o json | jq '.items[] | select(.status.containerStatuses[].ready==false) | {name: .metadata.name, status: .status.phase}'
    ```

---

## 📊 Custom-Columns Output Formatting

*   **Custom View of Node Resource Capacities**:
    ```bash
    kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.capacity.cpu,MEMORY:.status.capacity.memory,OS:.status.nodeInfo.osImage
    ```
*   **List Deployment Strategy Configurations**:
    ```bash
    kubectl get deployment -A -o custom-columns=NAME:.metadata.name,STRATEGY:.spec.strategy.type,MAX_SURGE:.spec.strategy.rollingUpdate.maxSurge
    ```

---

## 🛠️ Diagnostics & Emergency Troubleshooting

*   **Spin up an ephemeral network diagnostic toolkit pod**:
    ```bash
    kubectl run net-debug --rm -i --tty --image=nicolaka/netshoot -- sh
    ```
*   **Debug a running pod with an ephemeral sidecar**:
    ```bash
    kubectl debug -it <target-pod> --image=nicolaka/netshoot --target=<target-container>
    ```
*   **Check system event log sorted by timestamp**:
    ```bash
    kubectl get events -A --sort-by='.metadata.creationTimestamp'
    ```
*   **Capture heap dump/logs from container that crashed**:
    ```bash
    kubectl logs <crashed-pod> --previous --tail=100
    ```
*   **Download container files to local system**:
    ```bash
    kubectl cp <namespace>/<pod-name>:/app/logs/app.log ./local-app.log
    ```
