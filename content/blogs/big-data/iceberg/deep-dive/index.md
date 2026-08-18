---
title: "Iceberg Deep Dive: Metadata and Commits"
weight: 1
date: 2026-08-18
draft: false
description: "How Iceberg manifests plan scans, snapshots isolate readers, writers commit optimistically, and delete files change rows."
summary: "A technical walkthrough of Iceberg metadata trees, manifest pruning, atomic commits, sequence numbers, and row-level deletes."
tags: ["iceberg", "big-data", "lakehouse", "table-format", "tech"]
---

The [Iceberg introduction]({{< ref "/blogs/big-data/iceberg" >}}) explains why a
table needs explicit state beyond Parquet files. This deep dive walks the metadata
tree from a catalog pointer to scan tasks and then follows a writer's optimistic
commit.

## A snapshot is a metadata tree

The catalog resolves a table name to the current table metadata file. That JSON
file records schemas, partition specs, properties, snapshot history, and the
current snapshot. Each snapshot points to one manifest list, which points to
manifest files, which list data or delete files.

{{< mermaid >}}
flowchart TB
    Catalog[Catalog pointer] --> Metadata[Table metadata JSON]
    Metadata --> Snapshot[Current snapshot]
    Snapshot --> List[Manifest list]
    List --> M1[Data manifest]
    List --> M2[Delete manifest]
    M1 --> D1[Data file]
    M1 --> D2[Data file]
    M2 --> Delete[Delete file]
{{< /mermaid >}}

These files are immutable. A new commit creates new metadata and reuses unchanged
parts of the previous tree. This makes each snapshot a stable table view without
copying all table data or rewriting every manifest.

The manifest list stores information about each manifest, including its partition
spec, content type, file counts, sequence numbers, and partition summaries. A
manifest stores entries for data or delete files, including file path, partition
tuple, record count, file size, and column statistics.

## Planning prunes the tree top down

A scan starts with a row predicate and the selected snapshot:

{{< mermaid >}}
flowchart TB
    Predicate[Query predicate] --> Projection[Project onto partition transforms]
    Projection --> ManifestPrune[Prune manifest list entries]
    ManifestPrune --> Read[Read candidate manifests]
    Read --> FilePrune[Prune with partition and column metrics]
    FilePrune --> Tasks[Create file scan tasks]
    Tasks --> Engine[Distributed execution engine]
{{< /mermaid >}}

The manifest list acts as an index over manifests, so the planner need not open
every manifest. Candidate manifests then expose file-level bounds, null counts,
and partition data that can eliminate files without reading row data.

Pruning proves that a file cannot match; it does not usually prove that every row
matches. The execution engine still applies the row predicate after reading the
remaining files. Missing, stale, or overly broad metrics reduce pruning but must
not change correctness.

Each manifest belongs to one partition specification. After partition evolution,
old and new manifests coexist. The planner projects the same logical predicate
through the transform recorded for each spec.

## Writers commit optimistically

A writer does expensive data work before changing visible table state. It writes
new data or delete files, creates manifests, and prepares a new metadata tree
based on the table version it read.

{{< mermaid >}}
flowchart TB
    Base[Read base metadata pointer] --> Data[Write data and manifests]
    Data --> Candidate[Create candidate metadata]
    Candidate --> Compare{Catalog pointer unchanged?}
    Compare -->|yes| Swap[Atomic pointer swap]
    Compare -->|no| Validate[Refresh and validate conflict]
    Validate -->|compatible| Retry[Reuse files and retry metadata]
    Validate -->|conflict| Fail[Abort commit]
    Retry --> Compare
{{< /mermaid >}}

The catalog performs a compare-and-swap-like update from the base metadata
location to the candidate. If another writer committed first, the update fails.
The writer refreshes, checks whether the concurrent change conflicts with its
operation, and may reuse its immutable data files and manifests in a new attempt.

Readers that already selected the old snapshot continue to use it. New readers
resolve the new pointer. No reader observes half of the new file set.

Commit success can become ambiguous if the client loses its response after the
catalog accepted the swap. A writer must check commit status before deleting
files it believes are uncommitted; otherwise it can remove data referenced by a
successful snapshot.

## Sequence numbers order data and deletes

Iceberg v2 introduced data and file sequence numbers. They record the relative
age of file content and metadata so a planner can determine which delete files
apply to which data files without relying on wall-clock time.

Position deletes identify rows by data-file path and row position. Equality
deletes identify rows by values in selected fields. Format-version support is
important: newer Iceberg versions add mechanisms such as deletion vectors and
may deprecate older write patterns while retaining read compatibility.

Deletes are logical until files are rewritten or old snapshots expire. A query
may need to read a data file and apply matching delete information. Compaction can
materialize the result into new data files, but compaction itself is another
snapshot commit rather than an in-place edit.

## Metadata needs maintenance

Immutable metadata makes commits safe but creates ongoing work:

1. Compact small data files when scan overhead dominates.
2. Rewrite manifests when their count or size makes planning expensive.
3. Expire snapshots according to rollback and audit requirements.
4. Remove orphan files only with retention longer than the maximum expected write
   and commit duration.
5. Monitor commit retries, planning time, manifest counts, delete-file counts,
   and files scanned versus files selected.

Aggressive cleanup can violate a concurrent reader or writer's assumptions.
Maintenance is part of the table transaction design, not ordinary directory
housekeeping.

## Further reading

- [Iceberg branching and tagging](https://iceberg.apache.org/docs/latest/branching/)

## References

- [Iceberg specification](https://iceberg.apache.org/spec/)
- [Iceberg performance](https://iceberg.apache.org/docs/latest/performance/)
- [Iceberg configuration](https://iceberg.apache.org/docs/latest/configuration/)
