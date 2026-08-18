---
title: "Kafka Deep Dive: Logs and Replication"
weight: 1
date: 2026-08-18
draft: false
description: "How Kafka stores partition logs, replicates records, coordinates consumers, and provides idempotent and transactional writes."
summary: "A technical walkthrough of Kafka log segments, offsets, replication, consumer coordination, and delivery semantics."
tags: ["kafka", "big-data", "event-streaming", "distributed-systems", "tech"]
---

The [Kafka introduction]({{< ref "/blogs/big-data/kafka" >}}) explains the
partitioned log abstraction. This deep dive follows a record through the broker's
log, replicas, and consumer-group state.

## A partition is a segmented log

Each topic partition is one ordered log with monotonically increasing offsets.
On disk, Kafka divides that log into segment files. A segment is named from its
base offset and is accompanied by sparse indexes that map offsets and timestamps
to positions in the log.

{{< mermaid >}}
flowchart TB
    Producer[Producer record batch] --> Leader[Partition leader]
    Leader --> Active[Active log segment]
    Active --> Offset[Offset index]
    Active --> Time[Time index]
    Active --> Roll[Segment roll]
    Roll --> Closed[Closed segments]
    Closed --> Retention[Retention or compaction]
{{< /mermaid >}}

Records are grouped into batches so the producer, network, broker, and consumer
can amortize per-record overhead and preserve compression. The broker appends to
the active segment. When a size or time threshold is reached, it rolls a new
segment. Retention removes whole eligible segments rather than arbitrary records.

An offset is a logical position within one partition, not a global event ID.
Kafka first selects the segment containing an offset, then uses the sparse index
to seek near the record and scans forward.

Log compaction has a different contract from time or size retention. It keeps the
latest value observed for each key, plus tombstone behavior, so consumers can
reconstruct current keyed state. It does not turn Kafka into an arbitrary update-
in-place database.

## Replication follows one leader

One replica is leader for a partition; the others fetch from it as followers. The
leader orders appends. Replicas that remain sufficiently caught up form the
in-sync replica set used for safe leader election and acknowledgement decisions.

{{< mermaid >}}
flowchart TB
    Producer[Producer] -->|append| Leader[Leader replica]
    Leader --> F1[Follower replica 1]
    Leader --> F2[Follower replica 2]
    F1 --> ISR[In-sync replica set]
    F2 --> ISR
    Leader --> Committed[Committed log boundary]
    ISR --> Committed
    Committed --> Consumer[Consumer fetch]
{{< /mermaid >}}

With `acks=all`, the producer waits for the broker's strongest configured
acknowledgement. `min.insync.replicas` determines how many in-sync replicas must
be available for that write to succeed. Replication factor, acknowledgements,
minimum ISR, and unclean leader-election policy form one durability contract and
must be reasoned about together.

Idempotent production assigns sequence information so a retry does not append a
duplicate batch within the producer session. Transactions extend coordination
across writes to multiple partitions and offset commits. Consumers using
`read_committed` avoid records from aborted transactions.

## Consumer groups own partition assignments

A group coordinator manages group membership and committed offsets. The group
protocol assigns each subscribed partition to one consumer in the group. A
consumer fetches directly from partition leaders; the coordinator is control
plane, not a proxy for record data.

{{< mermaid >}}
flowchart TB
    Coordinator[Group coordinator] --> Assignment[Partition assignment]
    Assignment --> C1[Consumer 1]
    Assignment --> C2[Consumer 2]
    Leader0[Partition 0 leader] --> C1
    Leader1[Partition 1 leader] --> C2
    C1 --> Offsets[Committed group offsets]
    C2 --> Offsets
{{< /mermaid >}}

The consumer has at least three relevant positions: the next fetch position, the
last processed record, and the committed restart position. Committing before an
effect risks loss after failure; committing after an effect allows repetition.
The handler and destination determine whether repetition is harmless.

Rebalances change ownership. Long processing, missed heartbeats, membership
changes, or subscription changes can trigger reassignment depending on the group
protocol. Consumers must stop using revoked partitions before a new owner acts on
them, especially when processing has external side effects.

## Diagnose by partition

Cluster averages hide Kafka's unit of ordering and parallelism. Diagnose at the
partition and replica level:

1. Check leader distribution and unavailable or under-replicated partitions.
2. Compare follower lag and ISR changes with broker disk and network saturation.
3. Check produce request latency, batch size, compression, and retry rate.
4. Compare consumer end offsets, current positions, and committed offsets.
5. Look for hot keys, uneven partition bytes, and consumers with no assignment.
6. Correlate rebalance frequency with processing time and membership churn.

Adding consumers cannot increase one group's parallelism beyond its partition
count. Adding partitions can increase parallelism, but changes key distribution
and does not retroactively redistribute existing records.

## Further reading

- [Kafka tiered storage](https://kafka.apache.org/42/operations/tiered-storage/)

## References

- [Kafka log implementation](https://kafka.apache.org/42/implementation/log/)
- [Kafka distribution](https://kafka.apache.org/42/implementation/distribution/)
- [Consumer rebalance protocol](https://kafka.apache.org/42/operations/consumer-rebalance-protocol/)
