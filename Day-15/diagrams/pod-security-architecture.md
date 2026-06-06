# Pod Security Context Architecture

This diagram illustrates how Kubernetes Pod Security Context definitions are translated by the container runtime into Linux kernel-level isolation mechanisms.

```mermaid
graph TD
    subgraph PodSpec ["Pod Spec SecurityContext"]
        runAsUser["runAsUser: 10001"]
        readOnly["readOnlyRootFilesystem: true"]
        allowPriv["allowPrivilegeEscalation: false"]
        capDrop["capabilities.drop: [ALL]"]
        seccomp["seccompProfile: RuntimeDefault"]
    end

    subgraph Runtime ["Container Runtime (containerd + runc)"]
        configJSON["config.json (OCI Spec)"]
    end

    subgraph Kernel ["Linux Kernel Primitives"]
        Namespace["Namespaces (PID, Mount, Net, IPC)"]
        cgroups["cgroups (CPU, Memory limits)"]
        capabilities["Linux Capabilities (CAP_SYS_ADMIN, CAP_NET_ADMIN)"]
        LSM["AppArmor / SELinux (Mandatory Access Control)"]
        SecSyscall["Seccomp (Restricts system calls)"]
        MountOverlay["ReadOnly OverlayFS Mount"]
    end

    %% Mapping
    PodSpec -->|Configures| Runtime
    Runtime -->|Creates container using| Kernel

    runAsUser -->|Maps to| Namespace
    readOnly -->|Mounts as read-only| MountOverlay
    allowPriv -->|Sets PR_SET_NO_NEW_PRIVS flag| capabilities
    capDrop -->|Filters available| capabilities
    seccomp -->|Configures filters via| SecSyscall
    
    classDef spec fill:#2c3e50,stroke:#34495e,stroke-width:2px,color:#fff;
    classDef runtime fill:#f39c12,stroke:#d35400,stroke-width:2px,color:#fff;
    classDef kernel fill:#2980b9,stroke:#2471a3,stroke-width:2px,color:#fff;

    class PodSpec,runAsUser,readOnly,allowPriv,capDrop,seccomp spec;
    class Runtime,configJSON runtime;
    class Kernel,Namespace,cgroups,capabilities,LSM,SecSyscall,MountOverlay kernel;
```

### Kernel Hardening Features:
1. **Namespaces:** Provide isolation (e.g., a process inside the container cannot see processes on the host or in other containers).
2. **Capabilities:** Linux divides root privileges into distinct privileges (capabilities). Dropping `ALL` ensures even if a process runs as root inside the container, it cannot execute administrative actions (like changing routing tables).
3. **Seccomp (Secure Computing Mode):** Filters system calls (e.g., blocking `ptrace` or `sys_chroot`) that could be used for container escapes.
4. **AppArmor / SELinux:** Controls which files, network ports, and devices a containerized application can access.
