---
title: "Apache Spark: Why, What, and How"
weight: 1
date: 2026-08-11
draft: false
description: "An introduction to Apache Spark, from the need for distributed computation to jobs, stages, shuffles, and a first DataFrame pipeline."
summary: "Why Spark exists, what its execution model provides, and how to build and reason about a distributed data job."
tags: ["spark", "big-data", "data-engineering", "tech"]
---

Apache Spark is a distributed computation engine. It lets one program transform
data that is too large, too slow, or too operationally expensive to process on a
single machine.

This introduction follows one question through three layers: **why** Spark uses a
general DAG execution engine, **what** that engine provides, and **how** a Spark
application turns code into work across a cluster.

## Why Spark?

MapReduce established a reliable way to process large datasets across unreliable
machines, but its execution model is rigid: each job has map and reduce phases,
and multi-step or iterative algorithms pass intermediate results through durable
storage between jobs. Higher-level analytics therefore require chains of jobs
with repeated scheduling, serialization, and I/O.

Spark was created as a general DAG engine with reusable distributed datasets.
It can express several stages in one execution plan, pipeline compatible
operations, keep reused data in memory, and recover lost partitions from lineage.
Later structured APIs added relational planning and optimization without changing
the underlying distributed execution model.

Choose Spark when a workload benefits from a general-purpose distributed engine:
large batch transformations, SQL analytics, feature engineering, or iterative
processing that would be awkward as independent MapReduce jobs. Streaming is
available, but Spark's defining advantage is the unified DAG engine across
analytical workloads.

> [!NOTE]
> Spark does not make every job faster. Small data often runs more efficiently in
> a local process or database because a cluster adds scheduling, serialization,
> and network overhead.

## What is Spark?

Spark is an engine, not a storage system. It reads from systems such as object
storage, HDFS, Kafka, databases, and table formats including Iceberg, then writes
results back to storage.

Its main concepts are:

| Concept | Responsibility |
| --- | --- |
| Application | One submitted user program, consisting of a driver and its executors. |
| Driver | Runs the application, builds the execution plan, and coordinates work. |
| Cluster manager | Allocates worker resources to applications, for example Kubernetes, YARN, or Spark standalone. |
| Executor | A process on a worker node that runs tasks and stores cached data. |
| Job | The computation triggered by an action such as `count`, `collect`, or a write. |
| Stage | A group of tasks that can run without redistributing data. |
| Task | One unit of work, usually operating on one partition. |
| Partition | A slice of the distributed dataset and Spark's basic unit of parallelism. |

These terms form a hierarchy rather than synonyms. Submitting one application
starts one driver and acquires executors. The application can run many jobs. Each
job is divided into stages, and each stage launches roughly one task per input
partition for that stage.

The cluster manager decides which machines and resources the application receives;
Spark's scheduler decides which tasks run on those executors. Executors normally
belong to one application, so cached data and application state are not shared
directly between unrelated Spark applications.

In **client mode**, the driver runs in the submitting process, so losing that
machine loses the application. In **cluster mode**, the deployment system launches
the driver inside the cluster. This is an operational placement choice; both modes
use the same driver/executor execution model.

The preferred structured APIs are **DataFrames** and **Spark SQL**. They describe
the result you want rather than prescribing every execution step. Spark can then
optimize the logical plan before choosing a physical plan.

Spark evaluates transformations lazily. Calling `select`, `filter`, or `groupBy`
builds a plan; an **action** starts execution. This allows Spark to combine and
reorder work before sending tasks to executors.

{{< mermaid >}}
flowchart TB
    Code[DataFrame or SQL code] --> Logical[Logical plan]
    Logical --> Optimized[Optimized plan]
    Optimized --> Physical[Physical plan]
    Physical --> Job[Job]
    Job --> S1[Stage 1: parallel tasks]
    S1 -->|shuffle boundary| S2[Stage 2: parallel tasks]
    S2 --> Output[(Output data)]
{{< /mermaid >}}

The boundary between stages is usually a **shuffle**: data is repartitioned
across executors for operations such as joins, grouping, and global sorting.
Shuffles are necessary, but network transfer and disk spill make them one of the
first places to look when a job is slow.

### Narrow and wide dependencies

A narrow transformation such as `map` or `filter` lets each output partition read
from a small, known set of input partitions. It can usually be pipelined within one
stage. A wide transformation such as `groupBy`, `distinct`, repartitioning, or a
large join needs data from many upstream partitions and therefore introduces a
shuffle boundary.

During a shuffle, upstream tasks write partitioned shuffle blocks. Downstream tasks
fetch the blocks for their partition across the cluster. The cost includes network
traffic, serialization, sorting, open files, and possible disk spill. The number of
rows alone does not predict that cost: wide records, skewed keys, and an excessive
partition count can dominate it.

For `groupBy("country")`, every scan task may contain several countries. The
exchange routes each row to the stage-two partition responsible for its key:

{{< mermaid >}}
flowchart TB
    subgraph Stage1[Stage 1: input partitions]
        T0[Scan task 0]
        T1[Scan task 1]
        T2[Scan task 2]
    end
    T0 --> Exchange[Shuffle exchange by country]
    T1 --> Exchange
    T2 --> Exchange
    Exchange --> U0[Stage 2 task: CA keys]
    Exchange --> U1[Stage 2 task: CN keys]
    Exchange --> U2[Stage 2 task: US keys]
{{< /mermaid >}}

The country labels simplify the example: a real hash partition normally owns many
keys. The invariant is that all rows for one grouping key arrive at the same
downstream partition.

### Plans and optimization

DataFrame and SQL execution passes through several representations:

1. The unresolved logical plan records names and requested transformations.
2. Analysis resolves tables, columns, functions, and data types.
3. The optimizer rewrites the logical plan, for example by pushing filters toward
   scans and pruning unused columns.
4. Physical planning chooses executable operators and join strategies.
5. Runtime optimization can revise parts of the plan using observed statistics.

`explain("formatted")` connects the code to that physical plan. Look for scans,
filters, exchanges, sorts, aggregate operators, and the chosen join form. A plan
with an `Exchange` is explicitly moving data between partitions.

## How does a Spark job work?

Consider a daily event dataset. We want the number of completed orders and total
revenue per country.

```python
from pyspark.sql import SparkSession, functions as F

spark = SparkSession.builder.appName("daily-revenue").getOrCreate()

orders = spark.read.parquet("s3://warehouse/raw/orders/date=2026-08-10")

daily_revenue = (
    orders
    .filter(F.col("status") == "completed")
    .groupBy("country")
    .agg(
        F.count("order_id").alias("order_count"),
        F.sum("amount").alias("revenue"),
    )
)

daily_revenue.write.mode("overwrite").parquet(
    "s3://warehouse/reports/daily-revenue/date=2026-08-10"
)
```

The read, filter, grouping, and aggregation first form a logical plan. The write
is the action that submits a job. Spark can apply the filter within each input
partition, but grouping by `country` requires rows with the same key to meet on
the same reducer-side partition. That movement creates a shuffle and therefore
a new stage.

### Joins make distribution visible

For a large fact table joined with a small country lookup table, Spark may use a
broadcast join: the small side is sent to each executor so the large side does not
need to shuffle. When neither side is small enough, both sides commonly need to be
partitioned on the join keys.

Join decisions depend on statistics and configuration, so verify the physical
plan. Also inspect key distribution. A single country or placeholder key containing
half the rows can make one task much slower than its peers even when the total data
volume seems reasonable. Adaptive query execution can mitigate some runtime skew,
but it does not replace fixing meaningless hot keys or poor data modeling.

### Fault tolerance and persistence

Spark can recompute lost intermediate partitions from lineage: the driver knows
which transformations produced them and reschedules the necessary tasks. Shuffle
files and cached blocks have different lifetimes and recovery costs, so executor
loss may cause refetching or recomputation even when the application itself survives.

Caching is beneficial only when the same expensive result is reused. `cache()` is
lazy, consumes executor storage, and can evict other blocks. Materialize it with an
action, measure reuse, and `unpersist()` it when its lifetime ends. Persisting every
intermediate DataFrame usually increases memory pressure without avoiding useful
work.

### Operations playbook

Diagnose a slow job from the stage containing the straggler tasks. Compare task
duration, input rows, shuffle read bytes, spill, garbage collection, and locality:

- **One or a few tasks run far longer with much larger shuffle input:** the stage
  is skewed.
- **All tasks spill heavily:** partitions are too large for the available executor
  memory, or the operation materializes too much data.
- **Many tiny tasks spend little time computing:** file and partition counts are
  creating scheduling and open-cost overhead.
- **The driver stalls before tasks start:** planning, file listing, or an oversized
  query plan may be the bottleneck rather than executor capacity.

#### Immediate mitigation

For a skewed SQL join, confirm adaptive query execution and skew-join handling are
active, then inspect the executed plan to see whether Spark split the skewed shuffle
partition. Broadcast a genuinely small join side when executor memory and join type
make that safe. Filter and project columns before the exchange whenever semantics
allow it.

If one hot key remains, separate it from the common path or salt the large side of
the join and replicate the matching small-side row across the same salt buckets.
For a skewed aggregation, aggregate by `(key, salt)` first and merge those partial
aggregates by `key`. These changes add work and must preserve the operation's
associative or join semantics.

Adding executors helps only when Spark has runnable tasks. It cannot divide one
already-running straggler unless the plan or adaptive execution splits that work.
Avoid treating a larger cluster as the first response to one oversized partition.

#### Durable correction

Collect table and column statistics so the optimizer sees realistic cardinalities.
Choose partition counts from measured post-shuffle sizes, compact tiny source files,
and make key-frequency checks part of pipeline validation. Model placeholder and
unknown keys explicitly instead of allowing one null-like value to dominate joins.

Track stage p50 and p99 task duration, maximum-to-median partition size, shuffle
spill, executor loss, input file counts, and output file sizes. A successful run is
not sufficient if one task determines nearly all of its wall-clock time.

### A practical reasoning loop

When designing or diagnosing a Spark job, work in this order:

1. **Inspect the data.** Know its size, file format, partition layout, schema,
   and key distribution.
2. **Express the transformation with DataFrames or SQL.** Built-in operations
   expose more structure to the optimizer than opaque user-defined functions.
3. **Read the plan.** Use `daily_revenue.explain()` to see scans, exchanges,
   joins, and aggregations.
4. **Control data movement.** Filter early, select only needed columns, avoid
   accidental Cartesian products, and choose join strategies deliberately.
5. **Size partitions from evidence.** Too few underuse the cluster; too many
   increase scheduling overhead. Skewed keys may require separate treatment.
6. **Measure in the Spark UI.** Compare task duration, shuffle bytes, spill,
   input size, and failed or retried tasks.
7. **Check executor sizing.** Balance executor cores, memory, garbage collection,
   and task concurrency; a larger executor is not automatically a faster one.

> [!TIP]
> Start performance work with the physical plan and the Spark UI. Configuration
> tuning cannot repair an unnecessary shuffle, a severely skewed key, or millions
> of tiny input files.

### Where Spark fits

Spark commonly consumes events captured by Kafka, reads and writes Iceberg
tables, and complements Flink in platforms that need both strong batch analytics
and continuous event processing.

The useful mental model is simple: **your code declares a distributed data plan;
Spark optimizes it, divides it at data-movement boundaries, and schedules tasks
over partitions on executors.**
