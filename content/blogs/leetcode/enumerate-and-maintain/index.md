---
title: "Enumerate & Maintain"
weight: 6
date: 2026-08-10
draft: false
description: "A common problem-solving pattern: explore candidate states while preserving the information needed to evaluate them."
summary: "A common problem-solving pattern: explore candidate states while preserving the information needed to evaluate them."
tags: ["leetcode", "tech"]
---

Many algorithms can be understood as **enumerate and maintain**:

1. **Enumerate** the candidate states that might contain an answer.
2. **Maintain** just enough information about the current state to decide what to
   explore next, when to record an answer, and when to stop.

Enumeration answers, "What should I consider?" Maintenance answers, "What do I
already know about it?" The second part is usually where the algorithm becomes
efficient. Instead of recomputing a property for every candidate, update that
property as the search moves.

## The general shape

```text
initialize the first state and its summary

while there are states left to consider:
    inspect the current state

    if it is a valid answer:
        record or return it

    update the state summary
    choose the next state(s) to explore
```

The state summary depends on the problem. It may be a frequency table, a set of
visited nodes, a running sum, the current path, or a collection of choices that
remain available. A good summary supports the decisions the algorithm needs to
make without requiring a full scan of the current state.

## Related algorithms

- [Two Pointers]({{< ref "/blogs/leetcode/two-pointers" >}})
- [Sliding Window]({{< ref "/blogs/leetcode/sliding-window" >}})
- [Binary Search]({{< ref "/blogs/leetcode/binary-search" >}})
- [Graph Traversal]({{< ref "/blogs/leetcode/graph-traversal" >}})
- [Backtracking]({{< ref "/blogs/leetcode/backtracking" >}})
- [Monotonic Stack]({{< ref "/blogs/leetcode/monotonic-stack" >}})
- [Dynamic Programming]({{< ref "/blogs/leetcode/dynamic-programming" >}})
- [Sweep Line]({{< ref "/blogs/leetcode/sweep-line" >}})
- [Recursive Algorithm]({{< ref "/blogs/leetcode/recursive-algorithm" >}})

## Questions to ask

When approaching a search problem, make these two parts explicit:

1. What are the candidate states, and how will I enumerate them without
   omissions or unnecessary repetition?
2. What information must I maintain to test validity, choose the next move, and
   decide whether further exploration is worthwhile?

If the maintained state can be updated incrementally, the solution is often
much simpler and faster than checking every candidate from scratch.
