---
title: "Kubernetes Workload Lifecycle"
weight: 2
date: 2026-08-18
draft: false
description: "How Kubernetes controllers create Pods, the scheduler binds them, and kubelet starts and monitors containers."
summary: "A technical walkthrough from a workload object to scheduling, Pod sandbox creation, probes, termination, and failure diagnosis."
tags: ["kubernetes", "pods", "scheduling", "kubelet", "cloud-native", "tech"]
---

A workload manifest does not go directly to a container runtime. It moves through
several persisted objects and responsibility boundaries. Each component advances
only the part of the lifecycle it owns.

## From Deployment to process

{{< mermaid >}}
flowchart TB
    Deployment[Deployment] --> DeploymentController[Deployment controller]
    DeploymentController --> ReplicaSet[ReplicaSet]
    ReplicaSet --> ReplicaSetController[ReplicaSet controller]
    ReplicaSetController --> Pod[Unbound Pod]
    Pod --> Scheduler[kube-scheduler]
    Scheduler --> Binding[Pod bound to Node]
    Binding --> Kubelet[kubelet on selected Node]
    Kubelet --> CRI[Container runtime through CRI]
    CRI --> Sandbox[Pod sandbox]
    Sandbox --> Containers[Container processes]
    Containers --> Status[Pod status]
    Status --> Kubelet
{{< /mermaid >}}

The Deployment controller maintains ReplicaSets and rollout strategy. The
ReplicaSet controller maintains a replica count by creating or deleting Pod API
objects. The scheduler observes Pods without a Node assignment and writes a
binding. The kubelet observes Pods assigned to its Node and realizes them locally.

A bare Pod can skip the workload controllers, but it still needs scheduling and
node execution. Conversely, a controller can create a real Pod object but cannot
start its Linux process.

## Scheduling selects a Node

The scheduler maintains a queue of unscheduled Pods. For one Pod it broadly:

1. Filters out Nodes that violate hard requirements such as resource requests,
   node selectors, affinity, taints, volume constraints, or topology rules.
2. Scores feasible Nodes using placement preferences and balancing strategies.
3. Reserves and permits the choice where configured.
4. Binds the Pod by recording the selected Node through the API server.

Scheduling works from declared requests and cluster state. A CPU request affects
placement; a CPU limit affects runtime enforcement. A Pod with no feasible Node
stays Pending and is retried when relevant state changes.

The scheduler chooses a Node, not a container runtime instance or a specific GPU
by itself. Node-local managers and device interfaces complete those allocations
after binding.

## Kubelet realizes the Pod

For a bound Pod, kubelet coordinates node-local systems:

- The container runtime pulls images and creates a Pod sandbox and containers
  through the Container Runtime Interface (CRI).
- A Container Network Interface (CNI) plugin configures Pod networking.
- Container Storage Interface (CSI) components prepare and mount requested
  storage.
- Device plugins or Dynamic Resource Allocation drivers prepare special devices.
- kubelet runs probes, restarts containers according to policy, and reports status.

The Pod sandbox provides the shared environment for the Pod, notably its network
namespace. Application containers join it. The low-level OCI runtime ultimately
creates Linux processes, but Kubernetes reasons about the Pod object above them.

## Lifecycle states describe different layers

{{< mermaid >}}
stateDiagram-v2
    direction TB
    [*] --> Stored: API server accepts Pod
    Stored --> Unbound: spec.nodeName is empty
    Unbound --> Bound: scheduler binds Node
    Unbound --> Unbound: no feasible Node yet
    Bound --> Preparing: kubelet observes assignment
    Preparing --> RunningNotReady: sandbox and containers start
    Preparing --> Failed: setup cannot complete
    RunningNotReady --> Ready: readiness succeeds
    Ready --> RunningNotReady: readiness fails
    RunningNotReady --> Restarting: process or liveness fails
    Ready --> Restarting: process or liveness fails
    Restarting --> RunningNotReady: restart policy allows restart
    RunningNotReady --> Succeeded: process completes successfully
    Ready --> Succeeded: process completes successfully
    Restarting --> Failed: retry policy is exhausted
    Succeeded --> [*]
    Failed --> [*]
{{< /mermaid >}}

This is a system mental model, not a replacement for the official Pod phase and
container-state definitions. A Pod can be bound to a Node and still have phase
`Pending` while images, volumes, networking, or devices are prepared. A running
container can have Pod phase `Running` while readiness is false.

### Probes answer different questions

All three probes are executed by kubelet after the container starts:

| Probe | Question | Failure effect |
| --- | --- | --- |
| Startup | Has this slow-starting application finished initialization? | Kills the container after the threshold; suppresses the other probes until successful. |
| Readiness | Should this Pod receive Service traffic now? | Marks it not ready and removes it from eligible Service endpoints. |
| Liveness | Is this process stuck beyond useful recovery? | Kills the container so restart policy can act. |

Readiness does not restart a container. Liveness does not wait for readiness.
Poor liveness checks can turn temporary overload into a restart cascade, so use
them only for failures a restart can repair.

## Updates replace Pods

A Deployment rollout creates a new ReplicaSet from a changed Pod template and
gradually scales the new and old ReplicaSets according to `maxSurge` and
`maxUnavailable`. Existing Pods are not edited into the new template.

Deletion begins graceful termination. The API marks the Pod for deletion,
readiness is withdrawn from normal traffic, kubelet runs any `preStop` hook and
sends the container stop signal, then forces termination after the grace period.
Applications need signal handling and connection draining that fit this window.

PodDisruptionBudgets constrain voluntary disruptions such as node drains; they do
not prevent node loss, application crashes, or all direct deletions. Availability
still depends on replica count, topology, readiness, and rollout strategy.

## Diagnose where the lifecycle stopped

```sh
kubectl get pod <pod> -o wide
kubectl describe pod <pod>
kubectl get events --sort-by=.lastTimestamp
kubectl logs <pod> --all-containers
kubectl logs <pod> --previous
```

- No `nodeName`: inspect scheduler events, requests, selectors, affinity, taints,
  topology, and storage binding.
- `nodeName` set but still Pending: inspect image pulls, CNI, CSI, devices, mounts,
  sandbox creation, and node conditions.
- Running but not Ready: inspect readiness output and application dependencies.
- `CrashLoopBackOff`: inspect current and previous logs, exit reason, command,
  configuration, and liveness behavior.
- Terminating for too long: inspect finalizers, node reachability, hooks, and
  application shutdown.

## Further reading

- [Pod topology spread constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)

## References

- [Pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [Kubernetes scheduler](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)
- [Container Runtime Interface](https://kubernetes.io/docs/concepts/containers/cri/)
- [Liveness, readiness, and startup probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/)
