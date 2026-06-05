# 🏆 Day 14 Exercises: Production Networking Challenges

Apply your knowledge of CNI configurations, network routing, and security policies to solve these real-world enterprise infrastructure challenges.

---

## Challenge 1: Resolve CNI IPAM Pool Exhaustion

### Scenario
An e-commerce company scales up its batch processing engine during a holiday sale. The cluster runs on a physical node subnet of `192.168.10.0/24`. Calico CNI is configured with a default IPAM Block Size of `/26` (which allocates IP blocks of 64 addresses to each node). 

Suddenly, Node A starts failing to schedule new containers. Pods are stuck in `ContainerCreating` with the following error in the events:
`Failed to allocate IP address: CNI IPAM pool exhausted on node worker-node-a`

However, running `kubectl get nodes` shows that Node A is only running 28 active Pods, well below the 64 IP limit of the `/26` block.

### Tasks
1. Identify the architectural root cause: Why does the CNI block exhaustion happen even when fewer pods are active than the block size? (Hint: Think about IP allocation delegation, ephemeral pods, and block borrowing).
2. Write down the commands to check:
   * The Calico IPPool configurations.
   * The active IP allocations per block in the cluster.
3. Propose a solution: What changes would you make to the Calico IPPool resource definition (e.g. `blockSize` and CIDR size) to support high-churn, dense container scheduling in this subnet?

---

## Challenge 2: Define a Zero-Trust E-Commerce Policy Matrix

### Scenario
You are designing the network security policy for a secure credit card payment processing system. The architecture contains:
1. `checkout-frontend` (Namespace: `payments`): Web app, requires egress to the internet (payment gateway APIs) and ingress from the corporate proxy.
2. `payment-processor` (Namespace: `payments`): Middleware API, processes card details, requires access to the database and external verification services.
3. `payment-db` (Namespace: `secure-data`): Relational PostgreSQL database storing transaction history.
4. `kube-dns` (Namespace: `kube-system`): DNS resolver.

### Tasks
1. Complete the policy matrix below, indicating whether traffic is `ALLOWED` or `BLOCKED` between sources and destinations:

| Source Pod (Namespace) | Destination Pod (Namespace) | Port | Policy Action (Allow / Block) |
|---|---|---|---|
| `checkout-frontend` (`payments`) | `payment-processor` (`payments`) | `8080` | |
| `checkout-frontend` (`payments`) | `payment-db` (`secure-data`) | `5432` | |
| `payment-processor` (`payments`) | `payment-db` (`secure-data`) | `5432` | |
| `payment-db` (`secure-data`) | `payment-processor` (`payments`) | `Any` | |
| `checkout-frontend` (`payments`) | Internet | `443` | |
| `payment-db` (`secure-data`) | Internet | `Any` | |

2. Write the complete, valid Kubernetes `NetworkPolicy` YAML manifest to secure the `payment-db` Pod in the `secure-data` namespace, ensuring it only allows ingress from `payment-processor` in the `payments` namespace on port `5432`.

---

## Challenge 3: Debug a Cluster MTU Size Black Hole

### Scenario
An SRE deploys a new node pool consisting of VMs running on a different virtualization host system. Suddenly:
* Small HTTP requests (like health checks) between pods succeed.
* Large HTTP requests (like fetching a 10MB report file or starting a database sync) hang indefinitely and timeout.
* Running `ping -s 1450` between node interfaces fails.

The host physical network uses standard Ethernet with an MTU of `1500` bytes. The CNI is configured with the default VXLAN overlay network.

### Tasks
1. Calculate the theoretical maximum safe MTU size for the Calico VXLAN network interface (`vxlan.calico`) on the nodes. Show your calculations.
2. Write the commands to:
   * Inspect the current MTU size of the virtual interfaces inside a Pod.
   * Edit the Calico ConfigMap/IPPool to apply the corrected MTU configuration cluster-wide.
3. Explain the term "PMTUD (Path MTU Discovery) Black Hole" and why it causes large TCP connections to drop while small UDP/TCP queries succeed.
