---
title: "Kubernetes Deep Dives"
weight: 1
date: 2026-08-18
draft: false
description: "Focused guides to Kubernetes control-plane, workload, networking, storage, and extension internals."
summary: "Follow Kubernetes API objects through control loops, scheduling, node execution, networking, storage, and extension points."
tags: ["kubernetes", "cloud-native", "distributed-systems", "tech"]
orderByWeight: true
---

The [Kubernetes introduction]({{< ref "/blogs/cloud-native/kubernetes" >}})
provides the core mental model. These deep dives separate the major subsystems so
each can be understood without carrying the whole platform at once.

{{< mermaid >}}
flowchart TB
    API[Control plane and reconciliation] --> Lifecycle[Workload lifecycle]
    Lifecycle --> Node[Scheduling and node execution]
    Node --> Network[Networking and storage]
    API --> Extensions[Extension APIs and control loops]
    Extensions --> Lifecycle
{{< /mermaid >}}

Read them in this order:

1. **Control Plane and Reconciliation**: how API objects, etcd, List/Watch,
   informers, queues, and controllers converge.
2. **Workload Lifecycle**: how higher-level workloads create Pods, the scheduler
   binds them, and kubelet starts and monitors containers.
3. **Networking and Storage**: how replaceable Pods obtain connectivity, stable
   discovery, and persistent data.
4. **Extending Kubernetes**: how to choose among CRDs, controllers, admission,
   scheduler plugins, and node-level interfaces.
