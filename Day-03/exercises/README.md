# 🏆 Day 3 Daily Assignment: Architecture Internals Challenge

In this assignment, you will apply the architectural principles learned today to solve three hands-on engineering challenges.

---

## 🎯 Challenge 1: The Forbidden Node Bypass
**Scenario:** 
You have a node named `k8s-internals-worker` that has been cordoned (marked unschedulable) or tainted with `NoSchedule` for urgent maintenance. You have a critical debug container that **must** run on this node immediately.

### Requirements:
1. Taint the worker node:
   ```bash
   kubectl taint nodes k8s-internals-worker maintenance=active:NoSchedule
   ```
2. Write a pod manifest named `exercises/01-bypass-challenge.yaml` that runs the `nginx:alpine` image.
3. The pod **must not** contain any `tolerations` block.
4. When applied, the pod must schedule and run on `k8s-internals-worker` successfully, bypassing the scheduler's taint restrictions.

*Hint: Re-read the manual scheduling section in Lab 3.*

5. Clean up:
   ```bash
   kubectl delete pod -f exercises/01-bypass-challenge.yaml
   kubectl taint nodes k8s-internals-worker maintenance=active:NoSchedule-
   ```

---

## 🎯 Challenge 2: "Who Restarts the Container?" Analysis
**Scenario:**
Review the following situations and write a 1-paragraph explanation for each in a file named `exercises/answers.txt` explaining which component is responsible and why:

1. **Case A:** A container inside a running Pod crashes (exits with code 1) due to a memory leak.
   * *Which component detects this and restarts the container? Kubelet or ReplicaSet Controller? Why?*
2. **Case B:** A worker node suffers a power outage and shuts down completely.
   * *Which component detects the node failure and schedules replacement pods on other nodes? Kubelet or Controller Manager? Why?*

---

## 🎯 Challenge 3: Direct Secret Extraction from etcd
**Scenario:**
A secure database credentials secret is stored in Kubernetes. You must bypass the API Server and use `etcdctl` to retrieve the password directly from the raw database.

### Steps to set up:
```bash
# Create the secure secret
kubectl create secret generic db-credentials --from-literal=password="SuperSecret123"
```

### Requirements:
1. Exec into the control-plane node.
2. Formulate the `etcdctl` command to get the value of the key `/registry/secrets/default/db-credentials`.
3. In `exercises/answers.txt`, paste the raw output from etcd and explain why the password is not stored in plain-text JSON (describe the serialization format and base64 encoding).
4. Clean up:
   ```bash
   kubectl delete secret db-credentials
   ```

---

## 📤 Submission Checklist
Your `exercises/` folder should contain:
- [ ] `01-bypass-challenge.yaml` (The pod manifest that schedules on the tainted node)
- [ ] `answers.txt` (Your architectural explanations for Challenge 2 and raw output/analysis for Challenge 3)
