# 🎨 Day 02 Architecture Diagrams: Container Internals

This reference guide provides high-fidelity, production-grade Mermaid diagrams visualizing the architecture, lifecycle, and low-level Linux primitives that make up container technology.

---

## 1. Virtual Machine (VM) Architecture
Virtual Machines isolate applications by virtualizing physical hardware and running a complete, independent **Guest OS** on top of a hypervisor.

```mermaid
graph TD
    subgraph Host ["Physical Host Machine"]
        HW[Physical Hardware: CPU, RAM, NIC, Disk] --> HostKernel[Host OS Kernel]
        HostKernel --> Hypervisor[Hypervisor / VMM e.g., KVM, ESXi, Hyper-V]
        
        subgraph VM1 ["Virtual Machine 1 (Heavy isolation boundary)"]
            VirtHW1[Virtual Hardware: vCPU, vRAM, vNIC]
            GuestOS1[Guest OS: Full Kernel, Drivers, Init]
            AppA[Application A]
            
            VirtHW1 --> GuestOS1
            GuestOS1 --> AppA
        end

        subgraph VM2 ["Virtual Machine 2"]
            VirtHW2[Virtual Hardware: vCPU, vRAM, vNIC]
            GuestOS2[Guest OS: Full Kernel, Drivers, Init]
            AppB[Application B]
            
            VirtHW2 --> GuestOS2
            GuestOS2 --> AppB
        end
        
        Hypervisor --> VirtHW1
        Hypervisor --> VirtHW2
    end

    classDef default fill:#1a1c23,stroke:#707585,color:#fff;
    classDef highlight fill:#5d3fd3,stroke:#8a2be2,color:#fff;
    classDef app fill:#f72585,stroke:#fff,color:#fff;
    classDef guest fill:#3f37c9,stroke:#fff,color:#fff;
    
    class Hypervisor highlight;
    class AppA,AppB app;
    class GuestOS1,GuestOS2 guest;
```

---

## 2. Container Architecture
Containers share the host kernel. There is **no guest operating system** or virtualized hardware. The container runtime configures native kernel-level isolation policies.

```mermaid
graph TD
    subgraph Host ["Physical Host / Worker Node"]
        HW[Physical Hardware: CPU, RAM, NIC, Disk] --> Kernel[Shared Host Linux Kernel]
        
        subgraph Isolation ["Kernel Namespace & cgroup Isolation Boundary"]
            Kernel --> CR[Container Runtime: containerd / runc]
            
            subgraph Cont1 ["Container 1 (Process Isolation)"]
                AppA[Application A: PID 1]
                LibA[Libraries/Binaries]
                AppA --> LibA
            end
            
            subgraph Cont2 ["Container 2 (Process Isolation)"]
                AppB[Application B: PID 1]
                LibB[Libraries/Binaries]
                AppB --> LibB
            end
            
            CR --> Cont1
            CR --> Cont2
        end
    end

    classDef default fill:#1a1c23,stroke:#707585,color:#fff;
    classDef kernel fill:#03045e,stroke:#0077b6,color:#fff;
    classDef runtime fill:#7209b7,stroke:#fff,color:#fff;
    classDef app fill:#f72585,stroke:#fff,color:#fff;
    
    class Kernel kernel;
    class CR runtime;
    class AppA,AppB app;
```

---

## 3. Linux Namespace Isolation
Namespaces wrap a global system resource in an abstraction that makes it appear to processes within the namespace that they have their own isolated instance of the resource.

```mermaid
graph TB
    subgraph HostOS ["Host Operating System (Global Namespace)"]
        HostProc[Host Process Space: PIDs 1 to 32876]
        HostNet[Host Network: eth0, lo, routing table, iptables]
        HostMount[Host Mounts: /, /usr, /var, /etc]
        HostUsers[Host Users: root UID 0, user1 UID 1000]

        subgraph ContainerNamespace ["Container Isolated Namespace Namespace (ns)"]
            PIDns["PID Namespace: Sees only PIDs 1, 2, 3"]
            NETns["Net Namespace: Sees only eth0 (veth pair), lo"]
            MNTns["Mount Namespace: Sees only pivot_root overlayfs /"]
            USERns["User Namespace: Maps Container UID 0 -> Host UID 10001"]
        end
        
        HostProc -.->|Isolates PIDs| PIDns
        HostNet -.->|Isolates NICs/Ports| NETns
        HostMount -.->|Isolates Directories| MNTns
        HostUsers -.->|Maps Privileges| USERns
    end

    classDef default fill:#1e1e2f,stroke:#3f37c9,color:#fff;
    classDef ns fill:#7209b7,stroke:#fff,color:#fff;
    class ContainerNamespace fill:#12121e,stroke:#f72585,stroke-dasharray: 5 5;
    class PIDns,NETns,MNTns,USERns ns;
```

---

## 4. cgroups Resource Control
Control Groups (cgroups) limit, audit, and throttle resource consumption (CPU, Memory, I/O, Network) of process groups.

```mermaid
graph TD
    subgraph cgroupsRoot ["/sys/fs/cgroup (cgroups v2 Root)"]
        Kubepods["kubepods.slice (Kubelet resource tree)"]
        
        subgraph Burstable ["kubepods-burstable.slice (Burstable QoS Class)"]
            Pod1["pod_uuid_1.slice (Pod Container Group)"]
            Pod2["pod_uuid_2.slice (Pod Container Group)"]
            
            subgraph Cont1Limits ["Container 1 Resource Controller"]
                C1_CPU["cpu.max: '50000 100000'<br>(Limits to 0.5 CPU cores)"]
                C1_Mem["memory.max: '256M'<br>(Hard limit, OOMs if exceeded)"]
            end
            
            subgraph Cont2Limits ["Container 2 Resource Controller"]
                C2_CPU["cpu.max: 'max'<br>(Unlimited CPU)"]
                C2_Mem["memory.max: '512M'"]
            end
        end
    end

    Kubepods --> Burstable
    Pod1 --> Cont1Limits
    Pod2 --> Cont2Limits
    
    classDef default fill:#1a1c23,stroke:#707585,color:#fff;
    classDef slice fill:#3f37c9,stroke:#fff,color:#fff;
    classDef limit fill:#f72585,stroke:#fff,color:#fff;
    
    class Kubepods,Burstable,Pod1,Pod2 slice;
    class C1_CPU,C1_Mem,C2_CPU,C2_Mem limit;
```

---

## 5. OCI Runtime Lifecycle Flow
The Open Container Initiative (OCI) standardizes the runtime execution path.

```mermaid
sequenceDiagram
    autonumber
    actor User as Dev/Kubelet
    participant Docker as Docker CLI / Kubelet (CRI)
    participant Daemon as containerd (High-Level Runtime)
    participant Shim as containerd-shim (Process monitor)
    participant runc as runc (Low-Level OCI Runtime)
    participant Kernel as Linux Kernel

    User->>Docker: docker run / run Pod
    Docker->>Daemon: CRI Request: CreateContainer
    Daemon->>Daemon: Fetch & unpack OverlayFS image layers
    Daemon->>Daemon: Generate config.json (OCI Spec)
    Daemon->>Shim: Fork & exec containerd-shim
    Shim->>runc: Execute: runc create <id> --bundle <path>
    runc->>Kernel: Call syscalls: clone() (with namespaces), mount (OverlayFS), cgroups limits set
    runc-->>Shim: Container process created and suspended
    Shim->>runc: Execute: runc start <id>
    runc->>Kernel: Signal container entrypoint process to run
    runc-->>Shim: Exit (runc exits immediately after startup)
    Shim->>User: Pipe Stdout/Stderr & monitor container lifecycle
```

---

## 6. Docker Internal Architecture
Docker acts as a complete developer experience suite wrapping around `containerd`.

```mermaid
graph LR
    subgraph UserSpace ["Docker Engine User Space"]
        CLI[Docker CLI] -->|Unix Socket / HTTP JSON API| Daemon[dockerd daemon]
        Daemon -->|gRPC| containerd[containerd]
        containerd -->|gRPC| Shim[containerd-shim]
        Shim -->|executes| runc[runc]
    end
    
    subgraph KernelSpace ["Kernel Space"]
        runc -->|creates| Container[Isolated Container Process]
    end

    classDef default fill:#1a1c23,stroke:#707585,color:#fff;
    classDef cli fill:#0077b6,stroke:#fff,color:#fff;
    classDef daemon fill:#0096c7,stroke:#fff,color:#fff;
    classDef runtime fill:#7209b7,stroke:#fff,color:#fff;
    
    class CLI cli;
    class Daemon daemon;
    class containerd,Shim,runc runtime;
```

---

## 7. containerd Internal Architecture
`containerd` is the industry-standard high-level container runtime utilized directly by Kubernetes through the Container Runtime Interface (CRI).

```mermaid
graph TD
    subgraph containerd ["containerd Core"]
        CRI[CRI Plugin: Handles Kubelet gRPC APIs]
        Metadata[Metadata DB: Image/Container States]
        GC[Garbage Collector]
        
        subgraph Services ["Internal Services"]
            Content[Content Service: Content Addressable Blob Store]
            Images[Image Service: Image Manifests & Refs]
            Runtimes[Runtime Service: Tasks, Executions]
        end
    end
    
    Kubelet[Kubelet] -->|gRPC: CRI API| CRI
    CRI --> Metadata
    CRI --> Runtimes
    Images --> Content
    
    Runtimes -->|Spawns| Shim[containerd-shim]
    Shim -->|launches| runc[runc]
    
    classDef default fill:#1a1c23,stroke:#707585,color:#fff;
    classDef kubelet fill:#3f37c9,stroke:#fff,color:#fff;
    classDef runtime fill:#7209b7,stroke:#fff,color:#fff;
    
    class Kubelet kubelet;
    class CRI,Runtimes,Shim,runc runtime;
```

---

## 8. Process Isolation: Host vs. Container
The visual breakdown of how processes map between the host kernel view and the container view.

```mermaid
graph TD
    subgraph HostOS ["Host OS View (Real PID Space)"]
        systemd[systemd PID 1]
        systemd --> containerd[containerd PID 820]
        containerd --> shim[containerd-shim PID 1420]
        shim --> app_host[node server.js PID 1450]
        systemd --> bash[bash shell PID 1900]
    end

    subgraph ContainerOS ["Container View (Isolated PID Space)"]
        app_cont[node server.js PID 1]
    end
    
    app_host -.->|Directly corresponds to| app_cont
    
    classDef default fill:#1a1c23,stroke:#707585,color:#fff;
    classDef container fill:#f72585,stroke:#fff,color:#fff;
    classDef shim fill:#7209b7,stroke:#fff,color:#fff;
    
    class app_cont,app_host container;
    class shim shim;
```

---

## 9. Filesystem Layering (OverlayFS)
OverlayFS stacks multiple directory trees to form a unified root file system inside the container.

```mermaid
graph TD
    subgraph OverlayFS ["OverlayFS Mount Structure"]
        Merged[Merged Directory: /var/lib/containerd/overlayfs/.../merged<br>Combined view of all lower & upper directories. Container root /]
        
        subgraph ContainerLayer ["Container Writable Layer"]
            Upper[Upper Directory: /var/lib/containerd/overlayfs/.../diff<br>Stores newly created files, updates, and whiteouts of deleted files]
        end
        
        subgraph ImageLayers ["Read-Only Image Layers"]
            Lower2[Lower Directory 2: App Code & Node.js Binaries]
            Lower1[Lower Directory 1: Base Alpine OS Libraries]
        end
    end
    
    Upper --> Merged
    Lower2 --> Merged
    Lower1 --> Merged
    
    classDef default fill:#1a1c23,stroke:#707585,color:#fff;
    classDef write fill:#38b000,stroke:#fff,color:#fff;
    classDef read fill:#0077b6,stroke:#fff,color:#fff;
    classDef merged fill:#7209b7,stroke:#fff,color:#fff;
    
    class Upper write;
    class Lower1,Lower2 read;
    class Merged merged;
```

---

## 10. Container Lifecycle States
The finite state machine governing container execution.

```mermaid
stateDiagram-v2
    [*] --> Defined : OCI Bundle Configured (runc create)
    Defined --> Running : Process Executed (runc start)
    Running --> Paused : Process Frozen (cgroup freezers)
    Paused --> Running : Process Resumed (cgroup freezers)
    Running --> Stopped : Process Exited (Exit code 0 or >0)
    Running --> OOMKilled : Memory Threshold Exceeded (Out Of Memory Killer)
    OOMKilled --> Stopped : Captured Exit Code 137
    Stopped --> [*] : Directory Cleaned Up (runc delete)
```
