---
title: "Spark Deep Dive: Execution and Shuffle"
weight: 1
date: 2026-08-18
draft: false
description: "How Spark turns a logical query into stages and tasks, moves shuffle data, and recovers lost work."
summary: "A technical walkthrough of Spark plans, stage boundaries, shuffle files, lineage recovery, and performance diagnosis."
tags: ["spark", "big-data", "distributed-systems", "data-engineering", "tech"]
---

The [Spark introduction]({{< ref "/blogs/big-data/spark" >}}) presents Spark as
a general distributed DAG engine. This deep dive follows one query through that
engine and concentrates on the expensive boundary: the shuffle.

## From query to tasks

For DataFrame and SQL workloads, Spark first resolves names and types into an
analyzed logical plan. The optimizer rewrites that plan, then the planner selects
physical operators. An action turns the physical plan into a job.

{{< mermaid >}}
flowchart TB
    SQL[DataFrame or SQL] --> Logical[Logical plan]
    Logical --> Analyzed[Analyzed plan]
    Analyzed --> Optimized[Optimized logical plan]
    Optimized --> Physical[Physical plan]
    Physical --> Job[Job]
    Job --> Stage1[Stage: parallel tasks]
    Stage1 -->|shuffle| Stage2[Stage: parallel tasks]
{{< /mermaid >}}

A stage contains tasks that can run without repartitioning their input. Each task
normally handles one partition. A narrow dependency, such as `map` or `filter`,
lets one downstream partition read a small fixed set of upstream partitions and
can remain in the same stage. A wide dependency requires records from many
upstream partitions and creates a shuffle boundary.

## What a shuffle does

Suppose records are grouped by `customer_id`. Each map task computes the target
partition for every output record, buffers records by target, sorts or combines
them when appropriate, and writes shuffle blocks. Reduce tasks fetch their block
from every map task and merge the results.

{{< mermaid >}}
flowchart TB
    Input[Input partitions] --> Maps[Map tasks]
    Maps --> Blocks[Shuffle blocks partitioned by key]
    Blocks --> Exchange[Network fetch]
    Exchange --> Reduces[Reduce tasks]
    Reduces --> Output[Grouped output partitions]
{{< /mermaid >}}

This explains why an `Exchange` in a physical plan deserves attention. It can
include serialization, memory buffering, disk spill, many network connections,
and a synchronization point: a reduce task cannot finish until it has received
the required map outputs.

The number of output partitions controls task granularity after the exchange.
Too few partitions create large tasks and memory pressure. Too many create small
files and scheduling overhead. Adaptive Query Execution can coalesce small
shuffle partitions, change some join strategies, and split skewed partitions
using runtime statistics.

## Joins expose distribution

A broadcast join sends a small relation to executors and avoids repartitioning
the large relation. A sort-merge join usually repartitions both sides by the join
key and sorts within each resulting partition. The correct choice depends on
actual size and distribution, not only row count.

Skew breaks the assumption that partitions have similar cost. One hot key can
produce a reduce task much larger than its peers. The stage then appears nearly
finished while one task consumes most of the time. Fix the distribution or join
strategy before merely adding executors.

## Recovery follows dependency boundaries

Spark tracks how partitions were derived. If an executor loses a partition from
a narrow transformation, Spark can recompute it from its ancestors. Shuffle map
output is different: downstream tasks need those blocks, so lost map output may
require rerunning the producing map tasks.

Caching trades recomputation for memory or disk. Cache a reused, expensive
intermediate result, not every DataFrame. Cached data competes with execution
memory, and materialization occurs only after an action.

Driver failure and executor failure are not equivalent. Executors run tasks and
can be replaced; the driver owns application coordination. Driver availability
depends on the deployment mode and cluster manager.

## Diagnose from the plan downward

Use `explain("formatted")` and the Spark UI to connect intent to runtime evidence:

1. Find `Exchange`, join, aggregate, and sort operators in the physical plan.
2. Compare estimated and runtime row counts where statistics are available.
3. Check task duration distribution, not only the stage average.
4. Check shuffle read/write bytes, fetch wait, spill, and failed fetches.
5. Check executor GC time, peak memory, lost executors, and locality.
6. Check output partition counts and file sizes.

A slow Spark job is rarely explained by “the cluster is small” alone. The plan
defines data movement; partition sizes define task cost; the UI shows which
assumption failed.

## Further reading

- [Structured Streaming](https://spark.apache.org/docs/latest/streaming/)

## References

- [Spark SQL and DataFrames](https://spark.apache.org/docs/latest/sql-programming-guide)
- [SQL performance tuning](https://spark.apache.org/docs/latest/sql-performance-tuning)
- [Spark tuning](https://spark.apache.org/docs/latest/tuning.html)
