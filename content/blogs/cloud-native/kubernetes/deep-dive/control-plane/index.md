---
title: "Kubernetes Control Plane and Reconciliation"
weight: 1
date: 2026-08-18
draft: false
description: "How Kubernetes API objects, etcd, List and Watch, informers, work queues, and reconciliation form the control plane."
summary: "A technical walkthrough of Kubernetes API persistence, observation, concurrency, and controller mechanics."
tags: ["kubernetes", "control-plane", "controllers", "cloud-native", "tech"]
---

Kubernetes components coordinate through shared API objects. The control plane is
therefore easier to understand as a set of independent readers and writers around
one API boundary than as a chain of components calling one another.

## The API server is the boundary

{{< mermaid >}}
flowchart TB
    Clients[kubectl, controllers, schedulers, and kubelets] --> API[kube-apiserver]
    API --> Authn[Authentication]
    Authn --> Authz[Authorization]
    Authz --> Admission[Admission and defaulting]
    Admission --> Validation[Schema and invariant validation]
    Validation --> Etcd[(etcd)]
    Etcd --> Watch[Watch events]
    Watch --> Clients
{{< /mermaid >}}

The API server handles API versions, authentication, authorization, admission,
validation, persistence, and optimistic concurrency. etcd stores API server data;
ordinary controllers, schedulers, and kubelets do not read or write etcd directly.

An object version is identified by `metadata.resourceVersion`. A client can make
a conditional update based on the version it read. If another writer changed the
object first, the stale update conflicts and the client must read the new state
and recalculate instead of silently overwriting it.

`spec` and `status` separate intent from observation. Status is often exposed as
a subresource so permissions and concurrency can distinguish changing desired
configuration from reporting its result. Conditions add structured facts such as
`Available=False` with a reason and observed generation.

## List and Watch build an observation stream

Polling every object repeatedly would make the API server and clients redo work
when nothing changed. Kubernetes clients normally establish a snapshot and then
follow changes:

{{< mermaid >}}
flowchart TB
    List[List current objects] --> Reflector[Reflector manages List and Watch]
    Watch[Watch changes from resourceVersion] --> Reflector
    Reflector --> Cache[Local cache]
    Cache --> Handler[Event handler extracts object key]
    Handler --> Queue[Rate-limited work queue]
    Queue --> Reconcile[Reconcile latest state for key]
    Reconcile --> Write[Write through API server]
    Write --> Watch
{{< /mermaid >}}

Watch connections end, history is compacted, and notifications may repeat. Client
libraries handle relisting and reconnection. The local cache reduces API traffic
but can briefly lag; the durable API object remains the source of truth.

An event handler should normally enqueue a key such as `namespace/name`, not copy
an entire event into business logic. Several rapid changes can collapse into one
queue item. Reconciliation then reads the latest state and decides what is still
necessary.

## Reconciliation is level based

A robust controller answers “what must be true now?” rather than “what did this
event command me to do?”

{{< mermaid >}}
flowchart TB
    Load[Load desired and owned objects] --> Observe[Observe current facts]
    Observe --> Plan[Calculate next idempotent change]
    Plan --> Apply[Create, patch, or delete]
    Apply --> Status[Update status or conditions]
    Status --> Wait[Wait for Watch or retry]
    Wait --> Load
{{< /mermaid >}}

The loop must tolerate duplicate events, stale observations, partial progress,
process crashes, and retries. Usually one reconciliation makes a small change and
lets the resulting Watch event trigger the next pass. This keeps decisions local
and makes recovery equivalent to ordinary operation.

Owner references let garbage collection connect dependent objects to a controller
owner. Finalizers handle the opposite direction: they delay object deletion while
a controller performs external cleanup, then the controller removes its finalizer.
A finalizer without a live, retrying controller can leave an object terminating
forever.

## Availability does not mean shared mutation

Controllers can run several replicas, but leader election commonly ensures that
one replica performs active reconciliation for a given controller. Regardless of
leader election, API version conflicts remain the protection against concurrent
writers.

The API server and etcd require their own availability design. A highly available
control plane runs multiple API server instances and an etcd quorum. Losing a
worker node affects workloads; losing control-plane quorum prevents safe state
changes even if existing containers continue running temporarily.

## Diagnose the control path

When desired state does not converge:

1. Confirm the object exists in the expected API group, version, and namespace.
2. Inspect generation, resource version, status conditions, and events.
3. Check controller discovery, RBAC, leader election, queue retries, and logs.
4. Check whether an admission policy rejects or mutates the intended object.
5. Check owner references and finalizers before manually deleting dependents.
6. Treat direct edits to status or generated child resources as temporary evidence,
   because their owning controller may overwrite them.

## Further reading

- [API priority and fairness](https://kubernetes.io/docs/concepts/cluster-administration/flow-control/)

## References

- [Kubernetes API concepts](https://kubernetes.io/docs/reference/using-api/api-concepts/)
- [Controllers](https://kubernetes.io/docs/concepts/architecture/controller/)
- [etcd administration](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
