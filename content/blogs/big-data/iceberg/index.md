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

This introduction explains **why** a directory of Parquet files is not enough,
**what** Iceberg stores beyond the data itself, and **how** metadata and snapshots
turn file changes into atomic table commits.

## Why Iceberg?

Columnar files such as Parquet efficiently store analytical data, but a collection
of files does not by itself provide table semantics.

At scale, directory-based tables develop difficult edge cases:

- A reader may observe half of a multi-file overwrite.
- Listing millions of files is slow and can be inconsistent on some stores.
- Renaming a partition column can imply rewriting directory layouts.
- Changing partition strategy can break queries or force a full rewrite.
- Tracking exactly which files belong to a table version becomes application logic.

Iceberg moves table state into explicit metadata. Readers use a committed snapshot
rather than guessing table contents from paths. Writers create new files and then
atomically publish a new metadata pointer, so readers see either the old snapshot
or the new one.

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

### Table maintenance is part of operation

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
