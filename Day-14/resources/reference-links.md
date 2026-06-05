# Day 14 Reference Materials

Here are the official documentation resources, engineering blogs, and specifications to deepen your understanding of Kubernetes networking internals.

---

## Container Network Interface (CNI)
* [CNI Spec on GitHub](https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md): The official specification defining how runtimes interact with network plugins.
* [Kubernetes CNI Documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/): Official guide on configuring CNI in a cluster.

## Calico and BGP Routing
* [Calico Architecture Documentation](https://docs.tigera.io/calico/latest/reference/architecture/): Details on Felix, BIRD, Typha, and Calico configurations.
* [Calico eBPF Data Plane](https://docs.tigera.io/calico/latest/operations/ebpf/): Operational guide to enabling Calico's high-performance eBPF datapath.
* [BGP Peering Configurations](https://docs.tigera.io/calico/latest/networking/configuring/bgp): How to peer Calico with Top-of-Rack switches in bare-metal deployments.

## Linux Kernel Networking and Netfilter
* [Linux Netfilter Project](https://www.netfilter.org/): Explains the underlying iptables, connection tracking (`conntrack`), and NAT capabilities inside the Linux kernel.
* [IPVS Load Balancing](http://www.linuxvirtualserver.org/software/ipvs.html): Official details on the IP Virtual Server technology utilized by high-scale clusters.

## Industry Outage Analysis & Lessons Learned
* [Monzo: Clean up your IP links](https://monzo.com/blog/2019/12/16/clean-up-your-ip-links/): A famous real-world outage report detailing how Calico IP allocations and virtual link leaks brought down services.
* [GCP Cloud Egress Cost Calculator](https://cloud.google.com/vpc/pricing): Review cloud networking costs to understand the financial implications of cross-zone and cross-region traffic.
