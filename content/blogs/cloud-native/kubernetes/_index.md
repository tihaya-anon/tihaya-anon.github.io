---
title: "Kubernetes: Why, What, and How"
weight: 2
date: 2026-08-18
draft: false
description: "An intuitive introduction to Kubernetes through desired state, API objects, Pods, controllers, scheduling, and Services."
summary: "Why Kubernetes coordinates containers across machines, what its core abstractions provide, and how a Deployment becomes running Pods."
tags: ["kubernetes", "containers", "cloud-native", "devops", "tech"]
---

Docker gives an application a repeatable image and a container lifecycle on one
host. A production application usually needs another layer: several machines,
multiple replicas, controlled updates, stable discovery, resource placement, and
recovery when a process or machine fails.

Kubernetes coordinates those concerns through a declarative API. You describe
the state the cluster should maintain; independent control loops continuously
move the observed state toward it.

This introduction explains **why** Kubernetes uses desired state, **what** its
core objects represent, and **how** a Deployment becomes running containers.

## Why Kubernetes?

A container engine can start and stop containers, but a multi-machine system has
questions that are larger than one container:

- Which machine has enough CPU and memory for a new replica?
- What replaces a replica after its process or node fails?
- How do clients find healthy replicas when Pod addresses change?
- How can a release replace instances gradually and roll back if it fails?
- How should storage, configuration, credentials, and policy reach each workload?

Scripts can answer these questions for one application, but they tend to encode a
fragile sequence of commands. If a step fails halfway through, the script must
discover what already happened before it can continue safely.

Kubernetes was designed around reconciliation instead. A persisted object states
the desired result, such as three replicas of an image. Controllers repeatedly
compare that intent with observed resources and take the next idempotent action.
The same process handles initial creation, ordinary changes, and recovery.

Choose Kubernetes when many containerized workloads need a shared, extensible
control plane for placement, rollout, service discovery, policy, and recovery.
For a small application on one machine, Docker or Compose is usually easier to
operate. Kubernetes earns its complexity when the cluster-level control model is
the requirement.

## What is Kubernetes?

A Kubernetes cluster contains a **control plane** and one or more **worker
nodes**. Components do not normally form one synchronous command chain. They
observe and update API objects through the API server.

{{< mermaid >}}
flowchart TB
    User[kubectl, CI, or platform client] --> API[kube-apiserver]
    API <--> Etcd[(etcd)]
    API --> Controllers[kube-controller-manager]
    API --> Scheduler[kube-scheduler]
    API --> Kubelet[kubelet on each node]
    Controllers -->|create or update objects| API
    Scheduler -->|bind Pod to Node| API
    Kubelet -->|report status| API
    Kubelet --> Runtime[Container runtime]
    Runtime --> Processes[Container processes]
{{< /mermaid >}}

| Component | Responsibility |
| --- | --- |
| API server | Validates and serves the Kubernetes API; the shared coordination boundary. |
| etcd | Persists API server data as the cluster's durable state. |
| Controller manager | Runs built-in control loops for Deployments, Jobs, Nodes, and other resources. |
| Scheduler | Selects a suitable Node for each unscheduled Pod. |
| kubelet | Makes Pods assigned to its Node run and reports their status. |
| Container runtime | Pulls images and manages Pod sandboxes and containers through CRI. |

### Objects carry intent

Kubernetes components coordinate through API objects rather than direct function
calls. Most objects have three conceptual parts:

- `metadata` identifies and organizes the object with names, namespaces, labels,
  ownership, and versions.
- `spec` states the desired configuration supplied by a user or controller.
- `status` reports the state observed by the component responsible for it.

For example, a Deployment spec requests three replicas. Its controller creates a
ReplicaSet, which creates Pods. The status records how many replicas are available.
If a Pod disappears, the desired replica count remains three, so the controllers
create a replacement.

### Pods are the scheduling unit

A Pod is the smallest object Kubernetes schedules. It contains one or more
containers that share a network namespace and can share volumes. Containers in
one Pod are placed on the same Node and follow one Pod lifecycle.

Most applications should not create bare Pods. Higher-level workload objects own
them:

| Workload | Use |
| --- | --- |
| Deployment | Replaceable, usually stateless replicas and rolling updates. |
| StatefulSet | Replicas that need stable identity or storage association. |
| DaemonSet | One Pod on each eligible Node. |
| Job | Work that should run to completion. |
| CronJob | Jobs created on a schedule. |

### Services provide stable discovery

Pods are replaceable and their IP addresses change. A Service selects Pods by
labels and provides a stable virtual address and DNS name. EndpointSlices track
the current eligible backends. Readiness controls whether a Pod should receive
Service traffic; it does not decide whether the container should restart.

### Configuration and data have separate objects

ConfigMaps hold non-confidential configuration, Secrets hold sensitive values,
and volumes expose data to containers. PersistentVolumeClaims request storage
whose lifecycle can outlive one Pod. These objects keep runtime configuration and
durable data outside the container image.

Kubernetes has several distinct internal systems behind this model. Continue with
the [Kubernetes Deep Dives]({{< ref "/blogs/cloud-native/kubernetes/deep-dive" >}})
for control-plane mechanics, workload lifecycle, networking and storage, and
extension design.

## How does Kubernetes work?

The following manifest asks Kubernetes to run three web replicas and expose them
inside the cluster:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:alpine
          ports:
            - name: http
              containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: http
---
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
    - port: 80
      targetPort: http
```

Apply it and inspect the resources:

```sh
kubectl apply -f web.yaml
kubectl get deployment,replicaset,pods,service
kubectl rollout status deployment/web
```

The important path is a sequence of persisted objects and independent decisions:

{{< mermaid >}}
flowchart TB
    Manifest[Deployment manifest] --> API[API server persists Deployment]
    API --> DeploymentController[Deployment controller]
    DeploymentController --> ReplicaSet[ReplicaSet object]
    ReplicaSet --> ReplicaSetController[ReplicaSet controller]
    ReplicaSetController --> Pods[Three unbound Pod objects]
    Pods --> Scheduler[Scheduler selects Nodes]
    Scheduler --> Bound[Pods bound to Nodes]
    Bound --> Kubelet[kubelet prepares each Pod]
    Kubelet --> Runtime[Runtime starts containers]
    Runtime --> Ready[Ready Pods enter Service endpoints]
{{< /mermaid >}}

The Deployment controller does not start containers. The scheduler does not
create Pods. The kubelet does not choose a Node. Each component watches the API
objects relevant to its responsibility and writes its result back through the API
server.

Scale the Deployment by changing desired state:

```sh
kubectl scale deployment/web --replicas=5
kubectl get pods --watch
```

The controller creates two more Pods. If one Pod is deleted, the controller
creates a replacement because the Deployment still requests five replicas:

```sh
kubectl delete pod -l app=web --field-selector=status.phase=Running
kubectl get deployment/web
```

The exact Pod identity is disposable; the Deployment is the durable intent.

Update the image through the Deployment and follow the rollout:

```sh
kubectl set image deployment/web web=nginx:stable-alpine
kubectl rollout status deployment/web
kubectl rollout history deployment/web
```

For diagnosis, start with objects and events before entering a container:

```sh
kubectl describe deployment web
kubectl get pods -o wide
kubectl describe pod <pod-name>
kubectl get events --sort-by=.lastTimestamp
kubectl logs <pod-name>
```

Remove the example:

```sh
kubectl delete -f web.yaml
```

## A durable mental model

Kubernetes is an API-driven collection of control loops:

1. Objects persist desired and observed state.
2. Controllers decide what resources should exist.
3. The scheduler decides where an unbound Pod should run.
4. The kubelet realizes a bound Pod on one Node.
5. Services and storage give replaceable Pods stable dependencies.

The system does not rely on one perfect execution sequence. Components can
restart, events can repeat, and observations can be briefly stale. Reconciliation
works because current API state, not event history, is the basis for the next
idempotent action.

## Further reading

- [Kubernetes security concepts](https://kubernetes.io/docs/concepts/security/)
- [Multi-tenancy](https://kubernetes.io/docs/concepts/security/multi-tenancy/)

## References

- [Kubernetes components](https://kubernetes.io/docs/concepts/overview/components/)
- [Kubernetes objects](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
- [Workloads](https://kubernetes.io/docs/concepts/workloads/)
- [Services](https://kubernetes.io/docs/concepts/services-networking/service/)
