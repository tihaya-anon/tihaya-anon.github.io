---
title: "Docker: Why, What, and How"
weight: 1
date: 2026-08-18
draft: false
description: "An intuitive introduction to Docker through reproducible runtime environments, images, containers, and volumes."
summary: "Why Docker packages runtime environments, what images and containers represent, and how to build and run an application."
tags: ["docker", "containers", "cloud-native", "devops", "tech"]
---

Source code defines what a program should do, but source code alone does not
define the environment in which it runs. The language runtime, system libraries,
tools, configuration, filesystem, and startup command all influence the result.
Docker packages those runtime requirements into an image and creates isolated
processes, called containers, from that image.

This introduction explains **why** Docker made containers a practical software
delivery unit, **what** images and containers represent, and **how** to build and
run a small containerized application.

## Why Docker?

Physical machines and virtual machines can provide controlled environments, but
they define that environment at machine granularity. A virtual machine includes
a complete guest operating system and kernel. That is a useful isolation boundary,
but it is a heavy package when the goal is to run one application with a known set
of user-space dependencies.

Linux already provided primitives for isolated processes and resource limits.
Docker made those primitives usable as a software delivery workflow:

- A `Dockerfile` describes how to assemble an environment.
- An **image** packages the filesystem and default runtime configuration.
- A **registry** distributes versioned images.
- A **container** runs an image with explicit storage, network, and resource
  settings.

Choose Docker when an application and its user-space environment should travel
as one repeatable artifact across development, CI, and deployment. Docker does
not remove differences in CPU architecture, host kernels, external services, or
runtime configuration. It makes the application boundary explicit and gives that
boundary a standard lifecycle.

## What is Docker?

The two concepts to keep in mind first are **image** and **container**.

An image is a read-only template containing an application filesystem and
metadata such as its default command, environment variables, working directory,
and exposed ports. A container is a runnable instance of that image: an isolated
process with runtime configuration and its own writable filesystem layer.

One image can create many containers. Each container starts from the same image
content but has its own process state, network identity, and writable layer.

| Concept | Meaning |
| --- | --- |
| Dockerfile | Instructions for building an image. |
| Image | Immutable filesystem layers plus default runtime metadata. |
| Container | One runnable instance created from an image. |
| Registry | A service that stores and distributes images. |
| Volume | Data whose lifecycle is independent of a container. |

{{< mermaid >}}
flowchart TB
    Definition[Dockerfile + source] -->|build| Image[Image]
    Image -->|run| C1[Container 1]
    Image -->|run| C2[Container 2]
    Volume[(Volume)] --> C1
{{< /mermaid >}}

### Images are the repeatable artifact

Most Dockerfile instructions create image layers. Unchanged layers can be shared
between images and reused by the build cache. An image name normally includes a
repository and tag, such as `runtime-demo:1.0`.

A tag is a convenient label and can later point to different content. A digest,
such as `sha256:...`, identifies exact image content. Record the digest when a
deployment must resolve to the same bytes every time.

### Containers are runtime instances

Starting a container adds runtime settings and a thin writable layer to an image.
Stopping and restarting the same container preserves that layer. Removing the
container removes it.

The main process defines the container's lifetime. When that process exits, the
container stops. A container is therefore closer to an isolated process than to
a small virtual machine: Linux containers on one host share the host's kernel.

### Volumes outlive containers

Application data that must survive replacement should not depend on the container
writable layer. A named volume has a separate lifecycle, so a new container can
mount the same data at the same path.

A bind mount is different: it exposes a specific host path inside a container.
Bind mounts are convenient for source code and configuration during development,
but they couple the container to the host's paths and permissions.

### Ports connect network boundaries

Containers have their own network view. `EXPOSE 8080` in a Dockerfile documents
an expected container port; it does not make the port reachable from the host.
The runtime option `--publish 8080:8080` maps host port 8080 to container port
8080.

For the object formats and kernel mechanisms behind these abstractions, continue
with [Docker Deep Dive: Images and Isolation]({{< ref "/blogs/cloud-native/docker/deep-dive" >}}).

## How does Docker work?

Start with an existing image to see the runtime lifecycle:

```sh
docker run --detach \
  --name web \
  --publish 8080:80 \
  nginx:alpine
```

If the image is not present locally, Docker pulls it from a registry. Docker then
creates a container, connects its storage and network, and starts the image's
default process. Open `http://localhost:8080` to reach container port 80 through
the published host port.

Inspect the running container:

```sh
docker container ls
docker logs web
docker stats --no-stream web
```

Stop and remove it:

```sh
docker stop web
docker rm web
```

The `nginx:alpine` image remains locally and can create another clean container.

### Build an image

Create a small `index.html`:

```html
<!doctype html>
<html lang="en">
  <head><meta charset="utf-8"><title>Runtime demo</title></head>
  <body><h1>A reproducible runtime</h1></body>
</html>
```

Create `Dockerfile` beside it:

```dockerfile
# syntax=docker/dockerfile:1
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
```

Build and run the image:

```sh
docker build --tag runtime-demo:1.0 .
docker run --detach \
  --name runtime-demo \
  --publish 8080:80 \
  runtime-demo:1.0
```

The final `.` is the build context. `COPY` can read files from that context, so
exclude unrelated files and secrets with `.dockerignore`:

```gitignore
.git
.env
build/
```

Rebuilding after changing `index.html` creates a new image. Existing containers
do not change in place; replace them with containers created from the new image.

### Persist data deliberately

Create a volume and let two temporary containers use it:

```sh
docker volume create runtime-data
docker run --rm \
  --mount type=volume,source=runtime-data,target=/data \
  alpine sh -c 'date -u >> /data/events.log'
docker run --rm \
  --mount type=volume,source=runtime-data,target=/data,readonly \
  alpine cat /data/events.log
```

The containers disappear because of `--rm`, but the named volume remains. This
is the separation to preserve in production: replace containers freely while
managing durable data through an explicit storage lifecycle.

### Define runtime configuration with Compose

Docker Compose records ports, mounts, environment, and multiple services in
`compose.yaml` instead of a long sequence of `docker run` commands:

```yaml
services:
  web:
    build: .
    image: runtime-demo:1.0
    ports:
      - "8080:80"
```

```sh
docker compose up --build --detach
docker compose ps
docker compose down
```

The Dockerfile defines the image. Compose defines how one or more containers run.

## A durable mental model

{{< mermaid >}}
flowchart TB
    Source[Dockerfile + source] -->|build| Image[Image]
    Image -->|push / pull| Registry[(Registry)]
    Image -->|create| Container[Container]
    Container -->|start| Process[Running process]
    Process -->|stop| Container
    Container -->|remove| Gone[Writable layer removed]
    Volume[(Volume)] <-->|mount| Container
{{< /mermaid >}}

- **Build** turns a definition and context into an immutable image.
- **Create** adds runtime configuration and a writable layer to form a container.
- **Start** runs the container's main process.
- **Remove** deletes the container, while separately managed volumes remain.

The image is the repeatable artifact. The container is one runtime instance. The
volume holds data whose lifetime must not depend on that instance. Most Docker
commands are variations on this model.

## Further reading

- [Rootless mode](https://docs.docker.com/engine/security/rootless/)
- [Build attestations](https://docs.docker.com/build/metadata/attestations/)

## References

- [Docker overview](https://docs.docker.com/get-started/docker-overview/)
- [Docker storage](https://docs.docker.com/engine/storage/)
- [Docker build cache](https://docs.docker.com/build/cache/)
