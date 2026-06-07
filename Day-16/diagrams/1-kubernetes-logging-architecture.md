# Kubernetes Node-Level Logging Architecture

This diagram illustrates how container logs flow from a Pod to the physical files on the host node, and how container engines structure symlinks for easier shipper access.

```mermaid
graph TD
    subgraph Pod ["Pod Namespace"]
        Container[Container Process]
    end

    subgraph Runtime ["Container Runtime Engine"]
        Engine[containerd / CRI-O]
    end

    subgraph Filesystem ["Node Host Filesystem"]
        Stdout["Stdout/Stderr Streams (FD 1 & FD 2)"]
        RawLog["Raw Log File<br/>/var/log/pods/NAMESPACE_POD-NAME_UID/CONTAINER-NAME/0.log"]
        Symlink["CRI Symlink File<br/>/var/log/containers/POD-NAME_NAMESPACE_CONTAINER-NAME-ID.log"]
    end

    Container -->|Emits stdout/stderr| Stdout
    Stdout -->|Captured by CRI| Engine
    Engine -->|Writes to| RawLog
    RawLog -->|Symlinked to| Symlink
```

### Key Architectural Concepts:
* **Runtime Capture:** The container runtime daemon is responsible for capturing file descriptors 1 (`stdout`) and 2 (`stderr`) of the root container process and writing them to the host file system.
* **Storage Path Hierarchy:**
  * The raw source is stored in `/var/log/pods/` using a folder naming convention that includes the Pod UID to prevent conflicts during re-schedulings.
  * A flatter, readable symlink is generated under `/var/log/containers/` to help collectors easily query logs using filename pattern matching.
