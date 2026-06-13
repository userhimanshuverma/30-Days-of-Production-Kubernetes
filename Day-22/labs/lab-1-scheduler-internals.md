# 🛠️ Lab 1: Exploring Scheduler Internals

In this lab, you will inspect scheduler logs, query scheduling events, and understand how the scheduler chooses nodes.

---

## 🏃 Step 1: Query Scheduling Events for a Pod

When a Pod is scheduled, the scheduler issues a `Scheduled` event. If it fails, it issues a `FailedScheduling` event. Let's create a test Pod and inspect these events:

1. Deploy a basic test Pod:
   ```bash
   kubectl run test-pod --image=nginx:alpine
   ```

2. Immediately describe the Pod to check the events section:
   ```bash
   kubectl describe pod test-pod
   ```

3. Look at the bottom of the output for events:
   ```text
   Events:
     Type    Reason     Age   From               Message
     ----    ------     ----  ----               -------
     Normal  Scheduled  10s   default-scheduler  Successfully assigned default/test-pod to worker-node-01
     Normal  Pulling    9s    kubelet            Pulling image "nginx:alpine"
   ```

The `From` column confirms that the `default-scheduler` made the choice.

---

## 🏃 Step 2: Access Scheduler Logs on a Control Plane

If you run a local Kind or Minikube cluster, the scheduler runs as a static pod in the `kube-system` namespace.

1. Find the scheduler pod name:
   ```bash
   kubectl get pods -n kube-system -l component=kube-scheduler
   ```
   *Example Output*:
   ```text
   NAME                                     READY   STATUS    RESTARTS   AGE
   kube-scheduler-kind-control-plane        1/1     Running   0          45m
   ```

2. View the scheduler log stream:
   ```bash
   kubectl logs -n kube-system kube-scheduler-kind-control-plane | tail -n 20
   ```

You will see logs detailing scheduling attempts, caching updates, and leaderelection details.

---

## 🏃 Step 3: Increase Scheduler Verbosity (Optional/Advanced)

For debugging scheduling latency, you can increase log verbosity.

1. SSH into the control-plane container (for Kind):
   ```bash
   docker exec -it kind-control-plane bash
   ```

2. Edit the static pod manifest located at `/etc/kubernetes/manifests/kube-scheduler.yaml`:
   ```bash
   vi /etc/kubernetes/manifests/kube-scheduler.yaml
   ```

3. Add `--v=5` (detailed tracing) or `--v=10` (maximum debug logging including plugin scores) to the list of container arguments:
   ```yaml
     spec:
       containers:
       - command:
         - kube-scheduler
         - --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
         - --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
         - --bind-address=127.0.0.1
         - --kubeconfig=/etc/kubernetes/scheduler.conf
         - --leader-elect=true
         - --v=5  # Add this line
   ```

4. Save the file. The Kubelet will automatically reload the static pod.
5. Exit the container and watch the logs. You will now see log entries for every filtering and scoring decision.
   ```bash
   exit
   kubectl logs -f -n kube-system kube-scheduler-kind-control-plane
   ```
   *Expected Output*:
   ```text
   I0613 18:55:12.123456       1 scheduling_queue.go:943] "About to try scheduling pod" pod="default/test-pod"
   I0613 18:55:12.124567       1 generic_scheduler.go:342] "Filter nodes" pod="default/test-pod" feasibleNodes=3
   I0613 18:55:12.125678       1 generic_scheduler.go:489] "Score nodes" pod="default/test-pod" scores=[{Name:worker-01 Score:95} {Name:worker-02 Score:80}]
   ```
   *Note: Set the verbosity back to standard levels in production to avoid logging disk exhaustion.*
