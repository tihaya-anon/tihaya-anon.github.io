---
title: "Kubernetes Networking and Storage"
weight: 3
date: 2026-08-18
draft: false
description: "How Kubernetes gives replaceable Pods routable identities, stable Services, policy, and persistent storage."
summary: "A technical walkthrough of Pod networking, Services, EndpointSlices, CNI, DNS, PersistentVolumes, claims, and CSI."
tags: ["kubernetes", "networking", "storage", "cloud-native", "tech"]
---

Pods are deliberately replaceable, but applications need stable ways to reach
one another and durable places to store data. Kubernetes separates those stable
contracts from Pod identity.

## Pod networking comes first

Each Pod receives its own network namespace and IP address. Containers in the
same Pod share that namespace and communicate over `localhost`. The cluster's
network implementation must make Pod addresses routable according to the
Kubernetes network model.

Kubelet asks a CNI-compatible network plugin to configure the Pod sandbox. The
implementation might use bridges, overlays, routes, eBPF programs, cloud network
interfaces, or a combination; Kubernetes exposes the contract without requiring
one data plane.

{{< mermaid >}}
flowchart TB
    PodSpec[Bound Pod] --> Kubelet[kubelet]
    Kubelet --> Runtime[Runtime creates Pod sandbox]
    Runtime --> CNI[CNI plugin configures network]
    CNI --> Interface[Pod interface and IP]
    Interface --> PodNetwork[Cluster Pod network]
    PodNetwork --> Other[Other Pod IPs]
{{< /mermaid >}}

A host port or container image `EXPOSE` field is not the normal service-discovery
mechanism. Workloads communicate with Pod IPs or, more commonly, through Services.

## A Service stabilizes changing backends

A Service selector matches Pod labels. The EndpointSlice controller records the
current matching, ready endpoints. Cluster DNS gives the Service a stable name,
while a Service data-plane implementation routes connections to an endpoint.

{{< mermaid >}}
flowchart TB
    Client[Client Pod] --> DNS[Cluster DNS]
    DNS --> Service[Service virtual address]
    Service --> DataPlane[Service data plane]
    EndpointSlices[EndpointSlices from ready Pods] --> DataPlane
    DataPlane --> PodA[Pod A]
    DataPlane --> PodB[Pod B]
{{< /mermaid >}}

The data plane may be implemented by kube-proxy rules or another compatible
component. The Service object does not itself proxy packets. Readiness affects
EndpointSlice eligibility, which is why a running but unready Pod normally stops
receiving regular Service traffic.

Service types solve different exposure problems:

| Type | Contract |
| --- | --- |
| ClusterIP | Stable address reachable inside the cluster. |
| NodePort | A port exposed on each Node and forwarded to the Service. |
| LoadBalancer | Requests an external load balancer from an integration. |
| ExternalName | DNS alias to an external name; no Pod selector or proxying. |

Ingress and Gateway API resources describe HTTP, TLS, and other north-south
routing, but require a controller and data-plane implementation. Creating the API
object without an installed implementation does not expose traffic.

NetworkPolicy selects Pods and describes allowed ingress or egress. Enforcement
depends on the network plugin. A policy object in a cluster whose plugin does not
implement NetworkPolicy provides no packet filtering.

## Volumes separate data from containers

A Pod volume is mounted into one or more containers and follows the Pod's
lifecycle unless backed by persistent storage. Ephemeral volume types solve
scratch space, projected configuration, or node-local caching; they do not promise
data survival after Pod replacement.

Persistent storage has a control-plane and node path:

{{< mermaid >}}
flowchart TB
    Claim[PersistentVolumeClaim] --> Provisioner[CSI provisioner or existing PV]
    Provisioner --> PV[PersistentVolume]
    PV --> Binding[PVC bound to PV]
    Binding --> Scheduler[Scheduler considers volume topology]
    Scheduler --> Node[Pod bound to Node]
    Node --> CSI[CSI node plugin stages and publishes volume]
    CSI --> Mount[Volume mounted into Pod]
{{< /mermaid >}}

A **PersistentVolumeClaim** is a workload's request for capacity and access
modes. A **PersistentVolume** represents provisioned storage. A **StorageClass**
selects a provisioner and parameters for dynamic provisioning. CSI separates the
Kubernetes storage lifecycle from vendor-specific storage operations.

Reclaim policy controls what happens to a dynamically or statically provisioned
volume after its claim is deleted. Retain, delete, backup, and application-level
consistency are separate decisions; a PVC is not a backup.

Access modes describe supported attachment or mount behavior but do not replace
application concurrency control. A filesystem writable by several Pods does not
make a database safe for several independent writers.

## Stateful identity is explicit

StatefulSets give replicas stable ordinal names and can create one claim per
replica from volume claim templates. A replacement Pod can recover the same name
and volume association. Kubernetes preserves identity and attachment workflow; it
does not implement database replication, leader election, consistency, or backup.

Use a Deployment when replicas are interchangeable. Use a StatefulSet when stable
network or storage identity is part of the application's protocol, and understand
the application's own recovery rules before automating replacement.

## Diagnose the contract layer

For networking:

```sh
kubectl get pod -o wide
kubectl get service,endpointslice
kubectl describe service <service>
kubectl get networkpolicy
```

Confirm selectors match labels, endpoints are ready, DNS resolves, the destination
port is correct, and policy permits both directions required by the connection.

For storage:

```sh
kubectl get pvc,pv,storageclass
kubectl describe pvc <claim>
kubectl describe pod <pod>
```

Separate provisioning or binding failures from scheduler topology conflicts and
node-level attach or mount failures. They occur in different components and leave
different events.

## Further reading

- [Gateway API](https://gateway-api.sigs.k8s.io/)
- [Volume snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)

## References

- [Kubernetes network model](https://kubernetes.io/docs/concepts/services-networking/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Storage classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
