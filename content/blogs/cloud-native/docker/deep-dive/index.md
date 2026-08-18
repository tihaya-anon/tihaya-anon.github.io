---
title: "Docker Deep Dive: Images and Isolation"
weight: 1
date: 2026-08-18
draft: false
description: "A technical walkthrough of OCI image manifests, layers, container runtimes, namespaces, cgroups, and Linux container isolation."
summary: "How Docker resolves an OCI image into a filesystem and starts an isolated Linux process."
tags: ["docker", "containers", "oci", "linux", "cloud-native", "tech"]
---

The [Docker introduction]({{< ref "/blogs/cloud-native/docker" >}}) treats an
image as a repeatable artifact and a container as one runtime instance. This deep
dive opens both abstractions: what a registry actually stores, how layers become
a root filesystem, and which Linux mechanisms isolate the resulting process.

## An image is a graph of content

A container image is not one archive. In the OCI image model, a name resolves to
a small graph of JSON documents and binary blobs. Every link is a **descriptor**
containing a media type, byte size, and cryptographic digest.

{{< mermaid >}}
flowchart TB
    Name[Repository name + tag] --> Index[Image index]
    Index -->|linux / amd64| ManifestA[Image manifest]
    Index -->|linux / arm64| ManifestB[Image manifest]
    ManifestA --> Config[Image configuration]
    ManifestA --> L1[Layer blob 1]
    ManifestA --> L2[Layer blob 2]
    ManifestA --> L3[Layer blob 3]
{{< /mermaid >}}

An optional **image index** selects a manifest for a platform such as
`linux/amd64` or `linux/arm64`. This is how one tag can support several CPU
architectures without pretending that one binary works everywhere.

The selected **image manifest** points to one configuration object and an ordered
list of compressed filesystem layers. A simplified manifest looks like this:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:config...",
    "size": 7023
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:layer1...",
      "size": 32654
    }
  ]
}
```

The **image configuration** records the target OS and architecture, default
process settings such as `Entrypoint`, `Cmd`, `Env`, `WorkingDir`, and `User`, and
the uncompressed hashes of the root filesystem layers. The manifest describes
distribution; the configuration describes the default runtime and filesystem
identity.

Tags are outside this content graph and can move. Digests are inside it: changing
one byte changes the digest and therefore changes every descriptor above it.

Inspect a manifest without starting a container:

```sh
docker buildx imagetools inspect nginx:alpine
docker image inspect nginx:alpine
docker history nginx:alpine
```

## Layers become one root filesystem

Each layer is a filesystem changeset, commonly distributed as a compressed tar
archive. Applying the layers in order produces the image root filesystem. A later
layer can add or replace a path; special whiteout entries represent deletion of a
path inherited from an earlier layer.

The runtime does not normally copy the complete image for every container. A
storage driver presents the read-only image layers as one merged view and places
a writable container layer above them.

{{< mermaid >}}
flowchart TB
    Writable[Container writable layer]
    App[Application layer]
    Runtime[Language runtime layer]
    Base[Base filesystem layer]
    Writable --> App --> Runtime --> Base
{{< /mermaid >}}

When a process first changes a file inherited from a lower layer, a copy-on-write
filesystem copies that file into the writable layer and changes the copy. This is
efficient for small runtime changes but is the wrong lifecycle for databases and
other durable state. Volumes bypass the image-layer stack and are managed
separately.

Image layers are immutable, not necessarily confidential. Deleting a secret in a
later Dockerfile instruction does not remove it from the earlier layer that added
it. Build secrets must enter through an ephemeral secret mount rather than
`COPY`, `ARG`, or a committed environment value.

## From Docker API to Linux process

Modern Docker Engine separates API management, container lifecycle, and low-level
runtime work:

{{< mermaid >}}
flowchart TB
    CLI[docker CLI] -->|Docker API| Daemon[dockerd]
    Daemon --> Containerd[containerd]
    Containerd --> Shim[containerd shim]
    Shim --> Runtime[runc / OCI runtime]
    Runtime --> Kernel[Linux kernel]
    Kernel --> Process[Container process]
{{< /mermaid >}}

The exact components vary by platform and configuration, but the responsibility
split is durable:

1. Docker resolves the image and requested runtime configuration.
2. Image layers are downloaded, verified by digest, and unpacked into local
   content and snapshot storage.
3. Docker combines image defaults with command-line settings, mounts, networks,
   capabilities, and resource limits.
4. An OCI runtime bundle describes the root filesystem and process settings.
5. The low-level runtime asks the kernel to create the namespaces, control group,
   mounts, credentials, and process.
6. A supervisor keeps the container lifecycle manageable after the low-level
   runtime exits.

An OCI runtime creates a process; it does not keep a private kernel running for
that container.

## How isolation is assembled

No single kernel feature means “container.” The boundary is assembled from
several controls.

| Mechanism | What it controls |
| --- | --- |
| PID namespace | Which processes and process IDs are visible. |
| Mount namespace | The filesystem mount tree visible to the process. |
| Network namespace | Interfaces, routes, ports, and firewall rules. |
| UTS namespace | Hostname and domain name. |
| IPC namespace | System V IPC and POSIX message queues. |
| User namespace | Mapping container users and groups to host IDs. |
| Cgroups | CPU, memory, process-count, and I/O accounting or limits. |
| Capabilities | Fine-grained division of traditional root privileges. |
| Seccomp | Filtering of allowed system calls. |
| LSM profiles | Additional policy through AppArmor or SELinux. |

Namespaces primarily control visibility. Cgroups primarily control accounting
and resource use. Capabilities, seccomp, and LSM policy reduce authority. A secure
boundary needs all three questions answered: what can the process see, how much
can it consume, and what is it allowed to do?

### Root inside is still important

Without user-namespace remapping, UID 0 in a container is UID 0 on the host even
though namespaces and other controls restrict it. A kernel or runtime escape can
therefore have a larger impact than an escape from an unprivileged process.

Run the application as a non-root image user, drop unused capabilities, keep the
default seccomp profile, make the root filesystem read-only where possible, and
avoid privileged containers. Rootless Docker and user-namespace remapping add a
host identity boundary but have operational constraints of their own.

Mounting `/var/run/docker.sock` into a container gives that container control of
the Docker daemon. On a typical host, that is effectively host-level authority,
not a harmless way to let a tool list containers.

### Network isolation

For a bridge network, Docker creates a network namespace and a virtual Ethernet
pair. One end enters the container namespace; the other connects to a bridge on
the host. Routing and firewall rules provide outbound access and implement
published ports.

{{< mermaid >}}
flowchart TB
    Client[Host or external client] -->|host port 8080| Rules[NAT / firewall rules]
    Rules --> Bridge[Docker bridge]
    Bridge --> Veth[Virtual Ethernet pair]
    Veth --> Namespace[Container network namespace]
    Namespace -->|container port 80| Process[Application process]
{{< /mermaid >}}

Publishing a port changes host networking; `EXPOSE` changes only image metadata.
On a user-defined network, Docker also provides name resolution so containers can
connect by service name rather than by an ephemeral IP address.

### PID 1 and shutdown

The image command becomes PID 1 inside the PID namespace. PID 1 must reap orphaned
child processes and handle termination signals correctly. Shell-form commands
can accidentally make a shell PID 1 and prevent signals from reaching the
application.

Prefer exec-form commands:

```dockerfile
ENTRYPOINT ["/app/server"]
CMD ["--port", "8080"]
```

Use `--init` or Compose `init: true` when the application does not reap child
processes itself. On shutdown, Docker sends a termination signal, waits for the
grace period, and then forces the process to exit if it is still running.

## Inspect the boundary

Use inspection to connect the abstraction to the host:

```sh
docker inspect runtime-demo
docker top runtime-demo
docker stats --no-stream runtime-demo
docker exec runtime-demo cat /proc/1/status
```

On a Linux Docker host, compare the container's namespace identifiers with a host
process under `/proc/<pid>/ns`, and inspect its cgroup membership under
`/proc/<pid>/cgroup`. These are kernel objects, not metadata invented by the CLI.

When a container behaves unexpectedly, trace the same sequence Docker used:

1. Confirm the resolved image digest and platform.
2. Inspect image defaults and runtime overrides.
3. Check mounts and the writable layer.
4. Check namespace-specific networking and published ports.
5. Check cgroup limits and out-of-memory events.
6. Check capabilities, seccomp, and LSM denials.
7. Check PID 1 signal and child-process behavior.

## Further reading

- [Rootless mode](https://docs.docker.com/engine/security/rootless/)
- [Build attestations](https://docs.docker.com/build/metadata/attestations/)

## References

- [OCI image manifest](https://github.com/opencontainers/image-spec/blob/main/manifest.md)
- [OCI image configuration](https://github.com/opencontainers/image-spec/blob/main/config.md)
- [OCI image layers](https://github.com/opencontainers/image-spec/blob/main/layer.md)
- [Docker security](https://docs.docker.com/engine/security/)
