---
title: "Apache Kafka: Why, What, and How"
weight: 3
date: 2026-08-11
draft: false
description: "An introduction to Apache Kafka through durable event logs, topics, partitions, consumer groups, offsets, and delivery semantics."
summary: "Why Kafka decouples event producers and consumers, what its log model provides, and how records move reliably through a cluster."
tags: ["kafka", "big-data", "event-streaming", "data-engineering", "tech"]
---

Apache Kafka is a distributed event log. Producers append records to named
topics, Kafka retains those records, and consumers read them at their own pace.

This introduction follows the system from **why** teams need a durable boundary
between services, through **what** Kafka's log abstraction provides, to **how**
partitioning, offsets, and consumer groups work in practice.

## Why Kafka?

Direct service-to-service integration begins simply: an order service calls a
billing service, an inventory service, an email service, and an analytics API.
As consumers multiply, the producer accumulates dependencies. A slow consumer
can slow the request, a failed consumer can lose an update, and adding a new use
case requires changing the producer again.

Kafka inserts a durable event boundary:

- Producers publish without knowing every consumer.
- Consumers process independently and can replay retained history.
- Traffic spikes are buffered instead of immediately overwhelming downstream
  systems.
- The event stream becomes a shared record of facts for real-time and batch use.

Kafka is useful when events must be distributed reliably to multiple independent
systems. It is not automatically the right choice for synchronous request-response
calls, arbitrary record updates, or queues that require a global per-message
priority.

## What is Kafka?

A **record** contains a key, value, timestamp, and optional headers. Records are
appended to a **topic**, which is divided into ordered **partitions**. Each record
within a partition receives an increasing **offset**.

| Concept | Meaning |
| --- | --- |
| Broker | A Kafka server that stores partitions and serves clients. |
| Topic | A named stream of related records. |
| Partition | An ordered, append-only shard of a topic. |
| Replica | A copy of a partition used for durability and availability. |
| Partition leader | The replica that handles reads and writes for a partition. |
| Producer | A client that publishes records. |
| Consumer group | Consumers cooperating to divide a topic's partitions. |
| Group coordinator | The broker responsible for membership and offset operations for a group. |
| Offset | A record's position within one partition. |

Ordering is guaranteed **within a partition**, not across an entire multi-partition
topic. A producer key is therefore a design decision: records with the same key
are normally routed to the same partition, preserving their relative order.

Consumers do not remove records. Kafka retains data according to time, size, or
log-compaction policies. A consumer stores its progress as offsets and can reset
that position to replay data.

{{< mermaid >}}
flowchart TB
    P1[Order service] --> T[(orders topic)]
    P2[Payment service] --> T
    subgraph Kafka cluster
        T --> A[Partition 0]
        T --> B[Partition 1]
        T --> C[Partition 2]
    end
    A --> G1[Fraud group]
    B --> G1
    C --> G1
    A --> G2[Analytics group]
    B --> G2
    C --> G2
{{< /mermaid >}}

Each consumer group gets its own logical view of the topic. Within one group, a
partition is assigned to at most one consumer at a time. Adding consumers
increases parallelism only until the group has as many active consumers as topic
partitions.

### Consumer groups in detail

A consumer group is identified by `group.id`. All members with the same group ID
cooperate as one logical subscriber; a different group ID creates an independent
subscriber that can independently read the same retained records.

For a topic with six partitions, a group might be assigned like this:

| Group member | Assigned partitions |
| --- | --- |
| `consumer-a` | 0, 1 |
| `consumer-b` | 2, 3 |
| `consumer-c` | 4, 5 |

If a fourth member joins, the group redistributes the six partitions. If one
member fails, its partitions move to surviving members. If the group grows to
seven members, at least one member remains idle because a partition cannot be
split between two active members in the same group.

The group lifecycle has four important parts:

1. **Discovery.** A consumer connects through any bootstrap broker and discovers
   the broker coordinating its group.
2. **Membership.** The consumer joins the group, declares its subscriptions, and
   stays alive according to the active group protocol.
3. **Assignment.** An assignor maps subscribed partitions to members. Assignment
   strategy affects balance and how much ownership changes during scaling.
4. **Progress.** Members fetch assigned partitions and commit the next offsets
   the group should read after a restart or reassignment.

Kafka supports the classic and newer consumer group protocols. Their coordination
details differ, but the application-level contract is the same: group membership
changes can move partition ownership, so consumers must stop using revoked
partitions, finish or abandon in-flight work deliberately, and initialize newly
assigned partitions from the group's committed positions.

> [!IMPORTANT]
> A rebalance is not an error. It is the mechanism that restores work distribution
> after deployment, failure, scaling, or subscription changes. The engineering
> goal is to make rebalances infrequent enough, short enough, and safe for the
> consumer's side effects.

### Position, committed offset, and lag

These three values are related but not interchangeable:

- The **current position** is the next offset a live consumer will return for a
  partition.
- The **committed offset** is the durable recovery position stored for the group.
- The **log-end offset** is the broker's current end position for the partition.

Consumer lag is approximately `log-end offset - committed offset`. It answers how
far the durable group position trails the log, not how long a particular event has
waited. A slowly changing topic can have low record lag but high time lag; a busy
topic can have high record lag while consumers are still meeting a latency target.

The `auto.offset.reset` policy is used only when the group has no valid committed
offset for a partition. It does not continuously force a consumer to the earliest
or latest record.

### Polling and liveness

Consumers fetch records in batches through `poll()`. Group liveness and processing
liveness are separate concerns:

- Session and heartbeat settings detect a consumer process that disappears.
- `max.poll.interval.ms` bounds how long processing may go without another poll.
- `max.poll.records` limits how many cached records one poll returns to the
  application, which can help keep processing within that interval.

Long database calls or oversized batches can exceed the poll interval even when
the process is healthy. Kafka then reassigns the partitions, and the old consumer
must not continue applying results as though it still owns them. Keep the poll loop
responsive, bound per-batch work, and move expensive processing behind a carefully
designed handoff when necessary.

## How does Kafka work?

Follow an order event through the system:

1. The producer serializes the event and chooses the `orders` topic.
2. A partitioner uses the `order_id` key to select a partition.
3. The partition leader appends the record and replicates it to follower brokers.
4. The producer receives an acknowledgement according to its durability settings.
5. Consumers fetch batches from their assigned partitions.
6. Each consumer processes records and commits offsets that represent its progress.

### Leaders, replicas, and acknowledgements

Each partition has one leader and replica copies on other brokers. Producers and
consumers communicate with the leader. Followers replicate the leader's log and
can be elected when a broker fails, subject to the cluster's replica and election
rules.

Producer durability is shaped by `acks`, replication, and broker policy. Waiting
for all required in-sync replicas gives stronger durability than acknowledging
after only the leader appends. Idempotent production prevents retries from adding
duplicate records within the producer session and preserves ordering under the
supported retry configuration.

### Produce with a stable key

```python
producer.send(
    "orders",
    key=order["order_id"].encode("utf-8"),
    value=json.dumps(order).encode("utf-8"),
)
```

Using `order_id` keeps changes for one order together. If ordering instead matters
per customer, `customer_id` may be the better key. A hot key, however, concentrates
traffic on one partition and limits parallelism, so key cardinality and distribution
matter as much as meaning.

### Choose delivery behavior deliberately

Kafka participates in several delivery patterns:

- **At most once:** commit progress before processing; failures may lose work.
- **At least once:** process before committing; failures may repeat work.
- **Exactly once:** coordinate Kafka reads, writes, and offsets transactionally
  within supported Kafka workflows.

Most external side effects still need idempotency. For example, a database sink
can upsert by `event_id`, or record processed IDs in the same transaction as the
business update.

> [!WARNING]
> Retrying a producer without idempotence can create duplicates. Committing a
> consumer offset before its database transaction completes can lose an update.
> Delivery semantics depend on the whole workflow, not only the broker settings.

### Retention and compaction

Kafka's log is retained independently of whether consumers have read it. Two common
cleanup policies solve different problems:

- **Delete retention** removes old log segments after time or size limits.
- **Log compaction** retains the latest value for each key over time, while tombstone
  records represent deletions.

Compaction is useful for reconstructing the latest state of keyed entities, but it
does not turn Kafka into a low-latency point-lookup database. Consumers still read
the log to rebuild their local view, and duplicate or older values may remain until
compaction runs.

### Start with these design decisions

1. **Define the event contract.** Use stable event names, schemas, identifiers,
   and compatibility rules.
2. **Choose the partition key.** Align ordering with business identity while
   avoiding severe skew.
3. **Estimate partitions.** Account for throughput, consumer parallelism, and
   expected growth; increasing partitions later can change key-to-partition mapping.
4. **Set retention from replay needs.** Retention is a product and recovery
   requirement, not merely a disk setting.
5. **Make consumers idempotent.** Rebalances, retries, and crashes are normal.
6. **Monitor consumer lag.** Lag shows the distance between the latest offset and
   a group's processed position, but interpret it together with throughput and
   processing latency.
7. **Observe group stability.** Track rebalances, member churn, poll latency, and
   partitions assigned per member alongside lag.

The core model is: **Kafka stores ordered logs in partitions; producers append,
consumer groups divide the partitions, and offsets make progress replayable.**
