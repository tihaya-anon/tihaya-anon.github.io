---
title: "Apache Iceberg: Why, What, and How"
weight: 4
date: 2026-08-11
draft: false
description: "An introduction to Apache Iceberg through reliable analytical tables, metadata trees, snapshots, schema evolution, and partition evolution."
summary: "Why object-store data needs a table layer, what Iceberg metadata provides, and how atomic snapshots make large analytical tables reliable."
tags: ["iceberg", "big-data", "lakehouse", "data-engineering", "tech"]
---

Apache Iceberg is an open table format for large analytical datasets. It adds a
reliable table abstraction over data files in object storage or distributed file
systems, allowing multiple engines to read and write the same tables safely.

This introduction explains **why** Iceberg replaces path-based table state with
explicit metadata, **what** that metadata provides, and **how** snapshots turn
file changes into atomic table commits.

For manifests, scan planning, optimistic commits, and delete mechanics, continue
with [Iceberg Deep Dive: Metadata and Commits]({{< ref "/blogs/big-data/iceberg/deep-dive" >}}).

## Why Iceberg?

Hive-style tables derive much of their state from directory paths: partitions are
encoded in folder names, and query planning discovers data by listing those
folders or consulting a metastore that mirrors them. This couples the logical
table to its physical layout. On large object-store tables, file discovery is
expensive, renames are not atomic, concurrent changes are difficult to isolate,
and schema or partition evolution can require rewriting data or application logic.

Iceberg was designed to make table state explicit. Immutable metadata files track
the schema, partition specifications, snapshots, and exact data-file membership.
A writer prepares new files and metadata, then commits by atomically replacing one
catalog pointer. Readers plan from a selected snapshot instead of inferring the
table from a mutable directory tree.

Choose Iceberg when multiple engines need reliable SQL-table semantics over large
file-based datasets: atomic commits, consistent reads, time travel, and safe schema
or partition evolution. Parquet still stores the rows; Iceberg exists to provide
the table-level metadata and transaction boundary that a file format does not.

## What is Iceberg?

Iceberg separates the table's logical structure from its physical files.

| Layer | Responsibility |
| --- | --- |
| Catalog | Resolves a table name to its current metadata location and coordinates commits. |
| Metadata file | Describes schemas, partition specs, properties, snapshots, and history. |
| Manifest list | Identifies the manifests used by one snapshot. |
| Manifest file | Tracks data or delete files and partition-level statistics. |
| Data file | Stores table rows, commonly as Parquet, ORC, or Avro. |
| Delete file | Describes row-level deletions without immediately rewriting all data files. |

The catalog is the commit coordination point. It does not hold all table rows; it
maps a table identifier to the current Iceberg metadata location. Different catalog
implementations use different backing services, but every engine reading the table
must agree on the catalog and object-store identity rules or it may observe a
different table state.

A **snapshot** is a complete, immutable view of the table at a point in time. New
inserts, overwrites, and deletes produce new snapshots instead of mutating a shared
file list in place. Older snapshots enable time travel and rollback while their
referenced files remain available.

Iceberg also assigns stable IDs to columns. Schema evolution can therefore add,
drop, rename, or reorder fields without confusing a renamed column with an old
field at the same position.

Partitioning is similarly logical. A transform such as `days(event_time)` or
`bucket(16, customer_id)` is stored in metadata, so queries need not know physical
directory names. The partition specification can evolve as data volume and access
patterns change.

### Schema and partition evolution

Iceberg tracks columns by numeric field ID rather than only by name or physical
position. This is why a rename preserves the column's identity and why dropping a
column does not cause a newly added field to inherit old values accidentally.

Partition fields also have identities and transforms. If a table changes from
`months(event_time)` to `days(event_time)`, existing files keep their old partition
spec while new files use the new one. During planning, Iceberg evaluates each
manifest with the spec that wrote it. Partition evolution changes future layout;
it does not silently rewrite historical files.

Hidden partitioning means users filter on business columns such as `event_time`,
not a manually maintained `event_date` directory column. The engine projects that
predicate onto the applicable partition transforms for pruning.

One query can therefore plan across files written under different partition specs:

{{< mermaid >}}
flowchart TB
    Query[Filter on event_time] --> Planner[Iceberg scan planner]
    Planner --> Old["Old manifests: months(event_time)"]
    Planner --> New["New manifests: days(event_time)"]
    Old --> O1[(Historical data files)]
    New --> N1[(New data files)]
    Note[Partition evolution does not rewrite old files] -.-> Old
{{< /mermaid >}}

The planner projects the same row-level predicate onto each spec. Old and new
layouts coexist while queries continue to filter on the logical `event_time`
column.

{{< mermaid >}}
flowchart TD
    Catalog[Catalog: current metadata pointer] --> Meta[Table metadata]
    Meta --> S1[Current snapshot]
    Meta --> S0[Previous snapshot]
    S1 --> ML[Manifest list]
    ML --> M1[Manifest A]
    ML --> M2[Manifest B]
    M1 --> D1[(Data file 1)]
    M1 --> D2[(Data file 2)]
    M2 --> D3[(Data file 3)]
    M2 --> X1[(Delete file)]
{{< /mermaid >}}

## How does Iceberg work?

Suppose a Spark job appends one hour of orders:

```sql
INSERT INTO lakehouse.sales.orders
SELECT * FROM staging.hourly_orders;
```

The commit proceeds conceptually as follows:

1. Spark writes new data files without changing the visible table.
2. It creates manifests describing the added files and their statistics.
3. It writes a new manifest list and table metadata containing a new snapshot.
4. The catalog atomically swaps the table's current metadata pointer.
5. Readers starting afterward plan against the new snapshot; existing readers can
   finish against the snapshot they already loaded.

Concurrent writers use optimistic concurrency. A writer prepares work from a base
metadata version and attempts to commit. If another writer commits first, Iceberg
checks for conflicts and may retry against the new state. Operations that overlap
semantically can fail instead of silently corrupting the table.

Append operations can often retry after an unrelated concurrent append by applying
their new files to the latest metadata. Overwrites, deletes, and rewrites require
stronger conflict validation because another commit may have changed the same rows
or files. The catalog's atomic compare-and-swap style commit is what makes this
coordination possible without locking the table for the duration of data-file writes.

### Query planning uses metadata, not directory scans

When a query filters on date and customer, an engine can first prune manifests
using partition summaries, then prune data files using column statistics. Only the
remaining files need to be opened. This metadata tree keeps planning proportional
to relevant metadata rather than the total object count.

Planning proceeds from coarse to fine metadata:

1. Load the selected snapshot from table metadata.
2. Prune manifests using partition summaries in the manifest list.
3. Prune data files using partition values and file-level column metrics.
4. Apply relevant equality or position deletes to the remaining data files.
5. Split the selected files into scan tasks for the compute engine.

This is why metadata quality matters. Oversized manifest collections slow planning,
while missing or overly broad metrics reduce pruning and force the engine to open
more files.

```sql
SELECT customer_id, SUM(amount)
FROM lakehouse.sales.orders
WHERE order_time >= TIMESTAMP '2026-08-10 00:00:00'
GROUP BY customer_id;
```

### Row-level changes and delete files

An engine can implement updates and deletes in two broad ways:

- **Copy on write** rewrites affected data files and commits their replacements.
  Reads remain simple, but writes amplify work for scattered changes.
- **Merge on read** commits delete information and, for updates, new row versions.
  Writes are lighter, while readers must merge data and deletes until compaction.

Equality deletes identify rows by one or more field values. Position deletes
identify file paths and row positions. Table format version, engine support, and
workload determine which representation is available and appropriate.

### Snapshot history, branches, and tags

Snapshots form a history through parent snapshot IDs. Time-travel queries select
an older snapshot by ID or timestamp without copying the table. Named branches and
tags provide stable references to snapshots for workflows such as audit, testing,
or staged publication.

These references extend file lifetime. A snapshot cannot be fully cleaned up while
an unexpired branch or tag still needs it, so retention policies must account for
all references rather than only the main branch's current snapshot.

### Operations playbook

Separate planning, reading, and committing symptoms before adding compute:

- **Planning is slow before scan tasks start:** the table may have too many
  manifests, snapshots, or files to evaluate efficiently.
- **Reads open many small files:** frequent writes are producing files below the
  target size and amplifying object-store requests.
- **Reads spend time applying many deletes:** merge-on-read changes have accumulated
  delete files that need compaction.
- **Writers repeatedly fail commits:** concurrent operations overlap or the catalog
  and object store are responding slowly.
- **Metadata and storage continually grow:** snapshot, branch, tag, or orphan-file
  retention is keeping old files reachable.

#### Immediate mitigation

Rewrite small data files for the affected partitions rather than compacting the
entire table without a filter. Rewrite manifests when planning metadata is the
bottleneck, and compact delete files with their associated data when read
amplification is urgent. Run these operations with bounded concurrency and monitor
their own commits so maintenance does not overwhelm production writers.

Retry a commit only after determining whether its result is known and whether the
operation can safely rebase on the new snapshot. Blindly replaying an overwrite or
row-level change can conflict with concurrent data modifications.

Expire snapshots or remove orphan files only after validating branches, tags,
long-running readers, in-flight writers, rollback policy, and the configured safety
interval. These procedures reclaim storage; they are not reversible backups.

#### Durable correction

Set writer distribution and target file sizes from the table's arrival rate and
query pattern. Streaming writers often need a recurring compaction service because
latency-oriented commits naturally create smaller files. Align sort order and
partition transforms with selective filters without creating tiny physical
partitions.

Define maintenance objectives such as maximum small-file count, delete-file ratio,
manifest count, and snapshot age. Schedule compaction, manifest rewrites, snapshot
expiration, and orphan cleanup from those signals. Stagger maintenance across
tables and give every operation an owner, retry policy, and observable result.

### Routine table maintenance

Immutable files make commits reliable, but frequent writes can produce many small
files and old snapshots retain files that are no longer current. Production tables
therefore need scheduled maintenance:

1. Compact small data files into appropriately sized files.
2. Rewrite manifests when their layout no longer supports efficient planning.
3. Expire snapshots beyond the required rollback and audit window.
4. Remove orphan files only with a retention period that cannot race active jobs.
5. Monitor file counts, file sizes, snapshot age, metadata growth, and commit failures.
6. Compact delete files and data files according to measured read amplification,
   not only on a fixed calendar.

> [!CAUTION]
> Expiring snapshots and deleting orphan files are destructive maintenance actions.
> Retention must cover long-running readers, delayed jobs, rollback requirements,
> and the maximum duration of in-flight writes.

### Start with the table contract

Before creating a table, decide:

- Which catalog all engines will use and how commits are coordinated.
- Which schema changes producers are allowed to make.
- Which partition transforms match common filters without creating tiny partitions.
- Whether row-level changes use copy-on-write or merge-on-read behavior.
- How long snapshots remain available and who owns maintenance.

The core mental model is: **Iceberg does not replace Parquet or the compute engine;
it defines which files form a table, records their history in snapshots, and makes
metadata changes atomic.**
