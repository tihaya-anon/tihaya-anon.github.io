---
title: "Apache Flink: Why, What, and How"
weight: 2
date: 2026-08-11
draft: false
description: "An introduction to Apache Flink through continuous event processing, event time, state, watermarks, and checkpoints."
summary: "Why Flink exists, what stateful stream processing means, and how event time and checkpoints produce reliable results."
tags: ["flink", "big-data", "stream-processing", "data-engineering", "tech"]
---

Apache Flink is a distributed engine for stateful computations over data streams.
It treats incoming events as an unbounded dataset and updates results as those
events arrive.

This introduction explains **why** continuous processing needs a specialized
model, **what** Flink contributes, and **how** time, state, and recovery work
together in a running job.

## Why Flink?

Many questions lose value when answered tomorrow:

- Is this payment likely to be fraudulent?
- How many active sessions are on the site now?
- Has a device stopped reporting?
- Which account crossed a risk threshold in the last ten minutes?

A repeated batch job can approximate these answers, but each run rescans data
and introduces delay. A stream processor instead keeps the relevant computation
alive and updates it incrementally.

Continuous processing introduces harder correctness problems. Events can arrive
late or out of order. A keyed calculation must remember earlier events. Workers
fail while local state is changing. The system must recover without silently
losing data or applying the same effect twice.

Flink is designed around those problems rather than treating them as additions
to a batch-only execution model.

## What is Flink?

Flink models both bounded and unbounded data as streams. A job is a graph of
operators: sources emit records, transformations process them, and sinks deliver
results. Parallel instances of those operators run across task managers.

### From job to slot

Flink terminology spans the logical program and the physical runtime:

| Concept | Meaning |
| --- | --- |
| Job | The complete dataflow submitted for execution. |
| Operator | A logical transformation such as source, map, window, or sink. |
| Parallelism | The number of concurrent instances of an operator. |
| Subtask | One parallel instance of an operator. |
| Task | The runtime unit executed by one thread; it may contain a chain of operator subtasks. |
| Task slot | A TaskManager resource-allocation unit that can host a task pipeline. |
| JobManager | Coordinates scheduling, checkpoints, recovery, and cluster resources. |
| TaskManager | A worker process that offers slots and executes tasks. |

Suppose `source -> parse -> keyBy -> window -> sink` uses parallelism four.
Each operator has four subtasks. Compatible adjacent operators such as `source`
and `parse` may be **chained** into one task, avoiding serialization, buffering,
and thread handoff between them. A redistribution such as `keyBy` breaks that
forward chain because records must travel to the subtask responsible for each key.

{{< mermaid >}}
flowchart TB
    Job[Submitted job] --> Ops[Logical operator graph]
    Ops --> O0[Source + parse operators]
    Ops --> O1[Window + rule operators]
    O0 --> S0[Source + parse subtasks x4]
    O1 --> S1[Window + rule subtasks x4]
    S0 -->|operator chaining| T0[Source + parse tasks]
    S1 -->|operator chaining| T1[Window + rule tasks]
    T0 -->|keyBy network shuffle| T1
    T1 --> Slots[TaskManager slots]
{{< /mermaid >}}

A slot represents a share of a TaskManager's managed resources; it is not a
dedicated CPU core and does not by itself provide hard CPU isolation. With slot
sharing, subtasks from different operators in the same job can share a slot when
they belong to compatible slot-sharing groups. This makes it possible for one
slot to hold a pipeline while reserving resources across parallel pipelines.

With parallelism two and default slot sharing, two slots can each host one parallel
slice of the pipeline:

{{< mermaid >}}
flowchart TB
    subgraph TM[TaskManager]
        subgraph Slot0[Slot 0]
            A0[Source + parse task 0]
            B0[Window + sink task 0]
            A0 --> B0
        end
        subgraph Slot1[Slot 1]
            A1[Source + parse task 1]
            B1[Window + sink task 1]
            A1 --> B1
        end
    end
{{< /mermaid >}}

Slot sharing does not merge the two parallel slices. Subtask index 0 and its
downstream work share one slot; subtask index 1 uses another. This co-location
avoids reserving a separate slot for every operator while preserving parallel
pipelines across the available slots.

Increasing operator parallelism creates more subtasks and potential throughput,
but the cluster needs sufficient slots and the source and sink must support that
parallelism. A Kafka source, for example, cannot extract useful partition-level
parallelism beyond the partitions available to it.

### Job deployment and execution

The client builds a stream graph from the API calls and submits the job. Flink
turns that description into a schedulable job graph, requests slots, deploys tasks
to TaskManagers, and connects their data exchanges. The JobManager tracks task
state and coordinates recovery; TaskManagers exchange records directly during
execution.

For production, distinguish common deployment lifetimes:

- A **session cluster** can accept multiple jobs and shares cluster services.
- An **application cluster** is created for one application that may submit one
  or more jobs.
- A **per-job deployment** dedicates cluster resources and lifecycle to a single
  job where the chosen deployment target supports it.

The deployment choice changes failure isolation and resource ownership, not the
meaning of operators, tasks, or state inside a job.

Three more ideas define the processing model:

### Stateful operators

An operator can retain information between events. After `keyBy(customer_id)`,
all events for one customer reach the same logical keyed state. That state might
hold a counter, a recent pattern, a timer, or the contents of a window.

Flink distinguishes **keyed state**, scoped to the current key after `keyBy`,
from **operator state**, scoped to one parallel operator instance. Broadcast state
is a specialized operator-state pattern for distributing a control stream, such
as fraud rules, to every downstream subtask. This ownership determines how state
is redistributed when a job is rescaled.

Every stateful operator should use a stable operator UID in production. UIDs let
Flink map saved state back to the intended operator after code changes; relying on
automatically generated topology IDs makes upgrades fragile when the graph changes.

### Event time and watermarks

**Processing time** is the clock on the machine running the operator. **Event
time** is when the source says the event occurred. Event time produces results
that reflect the business timeline even when the network reorders records.

A **watermark** is the system's estimate that event time has progressed. When a
watermark passes the end of a window, Flink can evaluate that window. Events that
arrive behind the watermark are late and must follow the job's configured late
data policy.

Watermarks flow through the operator graph. An operator with multiple inputs is
generally constrained by its slowest active input watermark. An idle source
partition can therefore hold back downstream event time unless the source marks
it as idle. Watermark lag is often a symptom of an uneven or stalled input, not a
window implementation problem.

### Checkpoints

Flink periodically captures a consistent snapshot of operator state and source
positions. After a failure, it restores both and resumes from a coordinated
point. Exactly-once state consistency is possible when sources can replay data
and sinks participate in a compatible transactional or idempotent protocol.

{{< mermaid >}}
flowchart TB
    Kafka[(Kafka partitions)] --> Source[Source operator]
    Source --> Parse[Parse and validate]
    Parse --> Key[Key by customer]
    Key --> Window[10-minute event-time window]
    Window --> Rule[Evaluate risk rule]
    Rule --> Alerts[(Alert sink)]
    Coordinator[Checkpoint coordinator] -. barriers .-> Source
    Coordinator -. snapshot .-> Window
    Coordinator -. commit .-> Alerts
{{< /mermaid >}}

### Backpressure

Operators in a streaming job run concurrently. If a sink cannot accept records as
fast as its upstream operator produces them, network buffers fill and the pressure
propagates toward the source. This **backpressure** is useful because it bounds
uncontrolled buffering, but sustained backpressure means the pipeline's effective
throughput is below its input rate.

Find the first downstream operator that remains busy while its upstream is
backpressured. The remedy may be more parallelism, balanced keys, faster external
I/O, asynchronous calls, or a different sink contract. Adding source parallelism
cannot repair a bottleneck at the end of the graph.

## How does a Flink job work?

Suppose a job emits an alert when a customer spends more than $1,000 within ten
minutes. In Flink SQL, the core query could look like this:

```sql
SELECT
  customer_id,
  window_start,
  window_end,
  SUM(amount) AS total_amount
FROM TABLE(
  TUMBLE(TABLE payments, DESCRIPTOR(event_time), INTERVAL '10' MINUTES)
)
GROUP BY customer_id, window_start, window_end
HAVING SUM(amount) > 1000;
```

The query hides useful machinery:

1. SQL is translated into a graph of source, projection, exchange, window
   aggregation, filter, and sink operators.
2. The source assigns timestamps and emits watermarks.
3. Records are partitioned by `customer_id`, so one parallel operator owns each
   customer's window state.
4. Every payment updates the sum for its event-time window.
5. A watermark passing the window end triggers the calculation.
6. The sink receives the alert, subject to the chosen delivery guarantee.
7. Checkpoints preserve source offsets and the in-progress window state for
   recovery.

The exchange after keying is a physical network boundary. On each side, compatible
operators may be chained into tasks. Each parallel task occupies a slot according
to the job's slot-sharing rules and runs continuously until the bounded input ends,
the job is cancelled, or failure recovery restarts it.

### Time is part of the result

Imagine three events with event times `10:01`, `10:08`, and `10:04`, arriving in
that order. Processing-time logic observes the third event last. Event-time logic
can still place all three into the `10:00-10:10` window. The watermark decides how
long the job waits for stragglers before considering the window ready.

There is no universal watermark delay. A larger delay captures more late data but
holds results and state longer. A smaller delay reduces latency but increases the
chance that late events require correction or side output handling.

### Reliability requires an end-to-end contract

"Exactly once" is not a property to assume from the engine name. Check all parts
of the path:

- Can the source replay from a recorded position?
- Is operator state included in a consistent checkpoint?
- Can the sink commit atomically, or can it deduplicate retries?
- What happens to external side effects that Flink cannot roll back?

> [!IMPORTANT]
> A checkpoint is for automated fault recovery. A savepoint is an operator-managed
> snapshot used for controlled upgrades, migration, or rescaling. They are related,
> but they serve different operational purposes.

Checkpoint barriers travel with the data from sources through the graph. A task
snapshots its operators' state when the barrier conditions are satisfied, while
large state is persisted through the configured checkpoint storage and state
backend. A checkpoint is complete only after all required tasks acknowledge it.

Barrier alignment can increase checkpoint duration under backpressure because a
multi-input task may wait for barriers from slower inputs. Unaligned checkpoints
can reduce this delay by including in-flight data, trading checkpoint size and
recovery considerations for faster progress under sustained backpressure.

### Operations playbook

Use the Web UI at subtask granularity. Job-level averages hide the difference
between insufficient capacity and key skew:

- **All parallel sink subtasks are busy and upstream is backpressured:** the sink
  or its external system is the throughput limit.
- **One keyed subtask is busy while peers are idle:** one or a few keys own most
  of the records or state.
- **Checkpoint barriers take a long time to traverse the graph:** sustained
  backpressure or uneven inputs are delaying alignment.
- **Snapshot time is high without barrier delay:** state size, storage bandwidth,
  or the state backend is the likely bottleneck.
- **One input holds back watermarks:** inspect idle partitions, source lag, and
  timestamp assignment before changing window logic.

#### Immediate mitigation

If work is balanced, add TaskManager capacity and increase the bottleneck operator's
parallelism. Stateful rescaling should use a tested savepoint or supported checkpoint
workflow, stable operator UIDs, and a parallelism compatible with the operator's
maximum parallelism. More empty slots alone do not rescale a running operator.

For a slow external sink, increase sink parallelism only if the destination accepts
the concurrency. Otherwise batch requests, use bounded asynchronous I/O, or repair
the downstream service. For barrier delay under sustained backpressure, unaligned
checkpoints may improve checkpoint progress, but they do not fix a state-storage
bottleneck.

A single hot key still maps to one keyed-state subtask after rescaling. An emergency
path can route known heavy keys to a separate job or temporarily reduce their input
rate, but moving keyed state requires a controlled state migration and correctness
plan.

#### Durable correction

Split high-volume logical keys into stable subkeys and combine their partial results
in a second keyed stage. For example, aggregate `(customer_id, salt)` first, then
aggregate the partial values by `customer_id`. This increases parallelism at the
cost of another exchange and is valid only when the operation can be combined in
that way.

Keep remote calls asynchronous and bounded, set state retention from business
semantics, and size checkpoint storage for both steady state and recovery bursts.
Load-test with realistic key distributions, late events, and destination latency.
Track `busy`, `idle`, and `backpressured` time per subtask together with state size,
checkpoint alignment, snapshot duration, restart time, and watermark lag.

### A practical starting sequence

Begin with a small vertical slice:

1. Define the event schema, stable keys, and event-time field.
2. Decide the tolerated out-of-orderness and late-event policy from observed data.
3. Choose the minimum state needed for each key and set retention where appropriate.
4. Configure checkpoints and verify the source and sink guarantees.
5. Run a failure test: stop a worker, restore the job, and inspect duplicates,
   gaps, and recovery time.
6. Monitor backpressure, checkpoint duration, state size, watermark lag, and sink
   throughput.
7. Give stateful operators stable UIDs, then test a savepoint-based upgrade and a
   parallelism change before relying on them in production.

The durable mental model is: **Flink continuously moves events through an operator
graph while coordinating time, partitioned state, and recovery.**
