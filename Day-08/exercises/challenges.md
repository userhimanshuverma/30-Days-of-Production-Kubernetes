# 🏆 Day 08 Exercises — Storage Design Challenges

Put your platform engineering skills to the test with these three hands-on challenges. Write the manifests and commands to solve the scenarios in a live local or sandbox cluster.

---

## Challenge 1: Construct a Multi-Zone StorageClass
**Goal**: Design a StorageClass that ensures volumes are only provisioned in a specific set of Availability Zones (e.g. `us-west-2a` and `us-west-2b`) and waits until a Pod is scheduled before allocating the disk.

### Tasks
1. Write a StorageClass manifest named `regional-ssd` targeting the standard cloud block driver.
2. Include the parameter to restrict provisioning to `us-west-2a` and `us-west-2b`.
3. Set the volume binding mode to wait for scheduled pods.
4. Set the reclaim policy to `Retain`.

---

## Challenge 2: Deploy a High-Availability MongoDB StatefulSet
**Goal**: Deploy a MongoDB database that maintains three replicas (`mongo-0`, `mongo-1`, `mongo-2`) using dynamic storage provisioning and validates node eviction resilience.

### Tasks
1. Create a headless Service named `mongo-service` on port `27017`.
2. Create a StatefulSet named `mongo-db` with 3 replicas.
3. Configure the `volumeClaimTemplates` to request `15Gi` using your custom StorageClass.
4. Mount the volume to `/data/db`.
5. Deploy the StatefulSet and check the generated claims using:
   ```bash
   kubectl get pvc -l app=mongo
   ```
6. Simulate a node drain on the host of `mongo-1` and verify that when `mongo-1` starts on a new node, it attaches to the original `15Gi` volume and preserves its data.

---

## Challenge 3: Online Storage Resizing
**Goal**: Safely expand a running PostgreSQL database volume from `10Gi` to `30Gi` in-place while keeping the database application container online.

### Tasks
1. Deploy a test Pod using a dynamic PVC sized at `10Gi`.
2. Write records to the database volume.
3. Update the PVC manifest in-place to change resource capacity from `10Gi` to `30Gi` and apply it.
4. Monitor the status updates using `kubectl describe pvc` until you see the filesystem extension verify successfully.
5. Confirm that the data remains intact.
