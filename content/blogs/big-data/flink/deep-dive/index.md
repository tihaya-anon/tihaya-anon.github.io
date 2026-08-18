---
title: "Flink Deep Dive: State and Checkpoints"
weight: 1
date: 2026-08-18
draft: false
description: "How Flink partitions keyed state, takes distributed snapshots, aligns barriers, and restores a streaming job."
summary: "A technical walkthrough of key groups, state backends, checkpoint barriers, and recovery semantics."
tags: ["flink", "big-data", "stream-processing", "data-engineering", "tech"]
---

The [Flink introduction]({{< ref "/blogs/big-data/flink" >}}) explains the
stream-first model. This deep dive follows state from a keyed event through a
checkpoint and back into a recovered job.

## State follows partitioning

After `keyBy`, the key determines which operator subtask owns the event and its
state. Flink divides the key space into **key groups**. A subtask owns a range of
key groups, and the configured maximum parallelism fixes how many key groups
exist.

{{< mermaid >}}
flowchart TB
    Events[Keyed events] --> Hash[Key-group assignment]
    Hash --> KG0[Key groups 0-31]
    Hash --> KG1[Key groups 32-63]
    KG0 --> T0[Operator subtask 0]
    KG1 --> T1[Operator subtask 1]
    T0 --> State0[Local keyed state]
    T1 --> State1[Local keyed state]
{{< /mermaid >}}

Key groups are the rescaling unit. When parallelism changes, Flink reassigns
groups rather than reasoning about individual keys. The maximum parallelism
therefore limits future keyed-state parallelism and should be chosen deliberately.

The state backend owns the working representation of state, commonly JVM heap or
an embedded RocksDB-based store. Checkpoint storage is separate: it holds durable
snapshots, usually in distributed storage. Local working state makes event access
fast; durable snapshots make it recoverable.

## Barriers define a consistent cut

The checkpoint coordinator asks sources to record their positions and inject a
numbered barrier into each stream. Barriers travel in record order and divide
records that belong before and after the snapshot.

{{< mermaid >}}
flowchart TB
    Coordinator[Checkpoint coordinator] --> SourceA[Source partition A]
    Coordinator --> SourceB[Source partition B]
    SourceA -->|records then barrier n| Operator[Two-input operator]
    SourceB -->|records then barrier n| Operator
    Operator --> Snapshot[Snapshot state for n]
    Snapshot --> Storage[(Checkpoint storage)]
    Operator -->|barrier n| Sink[Downstream sink]
{{< /mermaid >}}

For an aligned exactly-once checkpoint, a multi-input operator pauses an input
after its barrier arrives until the matching barriers arrive on the other inputs.
It can then snapshot state containing all effects before barrier `n` and none
after it. The state data is written asynchronously so record processing can
continue after the snapshot point is established.

Alignment can become slow under backpressure or uneven inputs. Unaligned
checkpoints let barriers overtake queued records by including in-flight buffers
in the snapshot. This reduces alignment delay but increases snapshot I/O and does
not fix a checkpoint store that is already the bottleneck.

## Recovery restores state and input position

After a failure, Flink redeploys the dataflow, restores each operator from the
latest completed checkpoint, and asks replayable sources to resume at the saved
positions. Records processed after that checkpoint are processed again, but their
previous state effects were discarded with the failed attempt.

Exactly-once managed state does not automatically mean exactly-once external
effects. The sink must commit with the checkpoint, be transactional, or make
repeated writes idempotent. A non-transactional HTTP call cannot be rolled back by
restoring Flink state.

Savepoints use the same broad snapshot idea for planned operations such as
upgrades and rescaling. Stable operator UIDs preserve the mapping from saved state
to the intended operators when the program graph changes.

## Diagnose checkpoint health

Read checkpoint metrics as a path through the job:

1. Long start delay points to barriers moving slowly from sources.
2. Long alignment points to uneven or backpressured inputs.
3. Long asynchronous duration points to state size, local I/O, network, or
   checkpoint storage.
4. Large snapshots may reflect state growth or unaligned in-flight data.
5. Slow restore points to snapshot layout, storage throughput, and recovery
   parallelism.

Checkpointing cannot compensate for a job that never catches up. After recovery,
the job needs spare throughput to process replayed records while new records keep
arriving.

## Further reading

- [Flink application upgrades](https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/upgrading/)

## References

- [Stateful stream processing](https://nightlies.apache.org/flink/flink-docs-stable/docs/concepts/stateful-stream-processing/)
- [Fault tolerance](https://nightlies.apache.org/flink/flink-docs-stable/docs/learn-flink/fault_tolerance/)
- [Tuning checkpoints and large state](https://nightlies.apache.org/flink/flink-docs-stable/docs/ops/state/large_state_tuning/)
