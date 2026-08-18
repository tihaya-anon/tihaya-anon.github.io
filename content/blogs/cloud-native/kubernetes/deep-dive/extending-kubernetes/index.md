---
title: "Extending Kubernetes"
weight: 4
date: 2026-08-18
draft: false
description: "How to choose among Kubernetes CRDs, controllers, admission, scheduler plugins, and node-level extension interfaces."
summary: "A technical guide to Kubernetes extension boundaries and the responsibilities of declarative APIs, controllers, schedulers, and node plugins."
tags: ["kubernetes", "controllers", "crd", "operators", "cloud-native", "tech"]
---

Kubernetes is extensible at several layers. The difficult part is not finding a
hook; it is choosing the narrowest layer that owns the missing behavior. A custom
controller should not reimplement scheduling, and a scheduler plugin should not
manage a workload lifecycle.

## Prefer an existing API first

Before writing an extension, identify the exact decision the standard platform
cannot express:

| Requirement | Prefer |
| --- | --- |
| Replica lifecycle and rolling updates | Deployment, StatefulSet, Job, or another workload API. |
| CPU, memory, affinity, taints, topology spread | Built-in scheduling fields and plugins. |
| HTTP routing | Gateway API or Ingress with an implementation. |
| Persistent storage | CSI and storage APIs. |
| Special node-local hardware | Device plugins or Dynamic Resource Allocation. |
| Organization policy on API writes | Built-in policy APIs or admission policy. |
| A new declarative domain object | Custom resource plus controller. |
| A cluster-specific placement rule unavailable in standard APIs | Scheduler profile or plugin as a last resort. |

Extensions become additional production dependencies with APIs, upgrades, RBAC,
metrics, failure modes, and compatibility obligations. Reuse keeps those costs in
components that already own them.

## A CRD adds an API, not behavior

A CustomResourceDefinition registers a new resource schema and REST endpoint with
the API server. After installation, clients can create custom-resource objects
with `kubectl` like built-in objects.

Keep three identities distinct:

- **GVK**: API group, version, and kind identify an object's serialized type.
- **GVR**: API group, version, and plural resource identify its REST endpoint.
- **Language type**: a Go, Java, or other client representation used by code.

{{< mermaid >}}
flowchart TB
    CRD[CustomResourceDefinition] --> API[API server registers resource]
    API --> Object[Custom resource object]
    Object --> Controller[Custom controller watches object]
    Controller --> Children[Built-in or custom child resources]
    Children --> Status[Observed conditions]
    Status --> Object
{{< /mermaid >}}

The CRD provides storage, validation, discovery, and API conventions. It does not
start a controller or cause the custom object to affect the world. Behavior comes
from a separately deployed program that reads and writes API resources.

A good custom API states domain intent rather than exposing internal execution
steps. Its controller translates that intent into standard lower-level resources
and projects meaningful conditions back into status.

## Controllers must be reconstructable

Use the same List, Watch, cache, queue, and reconciliation model as built-in
controllers. The controller must derive its next action from API state after any
restart; an in-memory workflow position cannot be the only record of progress.

Owner references express dependent object ownership and enable garbage
collection. Finalizers protect external cleanup that Kubernetes cannot infer.
Status conditions should include reasons, messages, and observed generations so
users can distinguish current results from a stale observation.

Do not continuously overwrite entire child specs when another controller adds
defaults or owns fields. Use clear field ownership, patch only intended fields,
and treat immutable child fields as an API design constraint rather than fighting
them during every reconciliation.

## Admission changes API writes

Admission runs after authentication and authorization but before persistence.
Validating admission accepts or rejects a request; mutating admission can change
it. Prefer built-in validation, CRD schema rules, ValidatingAdmissionPolicy, and
other declarative mechanisms before operating a webhook.

A webhook is on the API write path. Its latency, certificate lifecycle,
availability, timeout, failure policy, side effects, and version compatibility
directly affect cluster operations. Mutation should be deterministic and
idempotent because clients and API servers retry.

## Scheduling extensions own placement only

The Scheduling Framework exposes stages such as queue sorting, pre-filter,
filter, score, reserve, permit, pre-bind, bind, and post-bind. A plugin implements
only the extension points it needs and is configured in a scheduler profile.

{{< mermaid >}}
flowchart TB
    Pod[Unscheduled Pod] --> Queue[Scheduling queue]
    Queue --> Filter[Filter infeasible Nodes]
    Filter --> Score[Score feasible Nodes]
    Score --> Reserve[Reserve and permit]
    Reserve --> Bind[Bind selected Node]
    Bind --> Kubelet[kubelet executes Pod]
{{< /mermaid >}}

A score plugin ranks Nodes already considered feasible. It cannot reliably provide
gang admission for a whole workload by looking at one Pod at a time, and it
should not duplicate resource, volume, taint, or affinity checks already owned by
built-in plugins.

Many placement requirements can be expressed with labels, affinity, topology
spread, taints, resource requests, or a higher-level queueing system. A custom
scheduler is justified only when the missing policy truly belongs to Node
selection.

## Node extensions realize local resources

Node-level interfaces have separate contracts:

- **CRI** connects kubelet to container runtimes.
- **CNI** configures Pod networking.
- **CSI** provisions, attaches, and mounts storage through controller and node
  components.
- **Device plugins** advertise and allocate countable extended resources.
- **Dynamic Resource Allocation** models richer device requests, selection, and
  preparation.

These interfaces integrate infrastructure with kubelet and scheduling. A custom
controller can create claims or Pods that use them, but should not reach into a
node and substitute for the responsible plugin.

## Trace responsibility before debugging code

When an extension appears broken, locate the last successful API boundary:

1. Was the new API registered and was the object admitted?
2. Did the controller observe it, create children, and update conditions?
3. Did any workload-level admission or quota system release Pods for creation?
4. Did the scheduler find and bind a Node?
5. Did kubelet and the node plugin prepare runtime, network, storage, and devices?

This ordering prevents a controller bug, scheduling constraint, and node plugin
failure from being collapsed into the same vague “Pod is Pending” diagnosis.

## Further reading

- [Operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)
- [API aggregation](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/apiserver-aggregation/)

## References

- [Extending Kubernetes](https://kubernetes.io/docs/concepts/extend-kubernetes/)
- [Custom resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [Admission controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
- [Scheduling Framework](https://kubernetes.io/docs/concepts/scheduling-eviction/scheduling-framework/)
- [Compute, storage, and networking extensions](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/)
