---
title: "Backtracking"
weight: 10
date: 2026-08-11
draft: false
description: "How to explore a decision tree while maintaining and restoring the current candidate."
summary: "How to explore a decision tree while maintaining and restoring the current candidate."
tags: ["leetcode", "tech"]
---
{{< katex >}}

> [!NOTE]- For those who come from Enumerate & Maintain
> Backtracking is an example of [Enumerate & Maintain]({{< ref "/blogs/leetcode/enumerate-and-maintain" >}}):
>
> - **Enumerate:** paths through a decision tree.
> - **Maintain:** the partial candidate and the information needed to reject impossible branches.
>
> Enumerate & Maintain is only a way to frame the problem. This article stands on its own, so feel free to skip this section.

## Principle

### A decision tree

Backtracking explores a sequence of choices. Each node in the resulting
decision tree is a **partial candidate**, and each edge adds one choice to that
candidate. A leaf may be a complete answer, an invalid candidate, or a branch
that cannot lead to an answer.

For example, when generating subsets of `[1, 2, 3]`, a node can store the
elements selected so far. From `[1]`, choosing `2` leads to `[1, 2]`; after all
subsets beginning with `[1, 2]` have been explored, the algorithm returns to
`[1]` and tries `3` instead.

This return to an earlier decision is the defining operation:

1. **Choose** one option and update the current state.
2. **Explore** every candidate that begins with that choice.
3. **Unchoose** the option, restoring the state for the next branch.

{{< tree-diagram
  nodes="[],[1],[],[1 2],[1],[2],[]"
  highlight="0,1,3"
  caption="Include-or-skip decisions for [1, 2]. After visiting the highlighted path [] -> [1] -> [1, 2], backtracking restores [1] and then [] before exploring their sibling branches."
>}}

Backtracking is therefore depth-first search over an implicit tree. The tree
usually does not exist as a data structure; recursive calls generate its nodes
only when they are visited.

### State and invariant

The current path is often stored in one mutable object such as `path`. Extra
state may make validity checks cheap: a set of used values, occupied columns,
or the remaining capacity of a combination.

A useful invariant is:

> On entry to `search(state)`, `path` contains exactly the choices from the root
> to this node, and every auxiliary structure describes that same path.

The recursive call may temporarily extend these objects. Before control
returns to its caller, it must restore them to their entry state. That makes
each sibling branch start from the same parent candidate.

> [!IMPORTANT]
> Undo every mutation made for a choice. If choosing updates both `path` and a
> `used` set, unchoosing must restore both. Otherwise, state from one branch
> leaks into the next branch and the invariant no longer holds.

## Template

The general shape is:

```python
answers = []
path = []


def search(state):
    if is_complete(state):
        answers.append(path.copy())
        return

    for choice in candidates(state):
        if not is_valid(state, choice):
            continue

        apply(state, choice)
        path.append(choice)

        search(next_state(state, choice))

        path.pop()
        undo(state, choice)
```

Not every problem needs every line. `state` may be only an index, `apply` and
`undo` may update only `path`, and a partial candidate may need to be recorded
before it is complete. The order remains the same: mutate, recurse, restore.

Use `path.copy()` when recording a mutable path. Appending `path` itself stores
another reference to the same list; later `append` and `pop` operations would
then change every recorded answer.

## Implementation: Subsets

[LeetCode 78: Subsets](https://leetcode.com/problems/subsets/) asks for every
subset of a list of distinct integers. A subset is determined by an increasing
sequence of source indices. After choosing index `i`, the next choice must come
from `i + 1` onward. This prevents both repetition and different orderings of
the same subset.

Every node is already a valid subset, including the root's empty path, so the
algorithm records `path` on entry rather than waiting for a leaf.

```python
class Solution:
    def subsets(self, nums: list[int]) -> list[list[int]]:
        answers: list[list[int]] = []
        path: list[int] = []

        def search(start: int) -> None:
            answers.append(path.copy())

            for i in range(start, len(nums)):
                path.append(nums[i])
                search(i + 1)
                path.pop()

        search(0)
        return answers
```

The recursive contract is: `search(start)` records every subset that extends
the current `path` using only indices from `start` onward. The loop chooses the
first new index; the recursive call enumerates all continuations after it.
Because the indices in every path are strictly increasing, each subset has
exactly one path through the decision tree.

There are \(2^n\) subsets. Copying a path can take \(O(n)\), so producing the
complete output takes \(O(n2^n)\) time. Excluding the returned answers, the
path and recursion stack use \(O(n)\) space.

## Implementation: N-Queens

[LeetCode 51: N-Queens](https://leetcode.com/problems/n-queens/) asks us to
place `n` queens so that no two share a row, column, or diagonal. Place one
queen per row. At depth `row`, the candidates are the columns in that row.

Three sets summarize the existing queens:

- `columns` stores occupied columns.
- `diagonal_down` stores `row - column`, which is constant on a `\` diagonal.
- `diagonal_up` stores `row + column`, which is constant on a `/` diagonal.

These sets let us reject an invalid placement in constant time, before
exploring the rest of its branch.

{{< tree-diagram
  nodes="1,1 3,x,1 3 0,x,-,-,1 3 0 2"
  highlight="0,1,3,7"
  caption="A successful N-Queens branch for n = 4 after placing the first queen in column 1. Each node lists columns by row; x marks a pruned sibling, and the highlighted path reaches the solution [1, 3, 0, 2]."
>}}

```python
class Solution:
    def solveNQueens(self, n: int) -> list[list[str]]:
        answers: list[list[str]] = []
        queens: list[int] = []
        columns: set[int] = set()
        diagonal_down: set[int] = set()
        diagonal_up: set[int] = set()

        def search(row: int) -> None:
            if row == n:
                board = []
                for column in queens:
                    board.append("." * column + "Q" + "." * (n - column - 1))
                answers.append(board)
                return

            for column in range(n):
                down = row - column
                up = row + column
                if (
                    column in columns
                    or down in diagonal_down
                    or up in diagonal_up
                ):
                    continue

                queens.append(column)
                columns.add(column)
                diagonal_down.add(down)
                diagonal_up.add(up)

                search(row + 1)

                queens.pop()
                columns.remove(column)
                diagonal_down.remove(down)
                diagonal_up.remove(up)

        search(0)
        return answers
```

On entry to `search(row)`, `queens` describes one valid queen in each row from
`0` through `row - 1`, and the three sets describe exactly those queens. A
candidate that conflicts with a set is pruned. Otherwise, the four mutations
establish the invariant for `search(row + 1)`, and the four inverse mutations
restore it afterward.

Without pruning, there are \(n^n\) ways to choose one column per row. Rejecting
occupied columns ensures that the algorithm explores at most \(n!\) complete
column arrangements, and diagonal checks prune the tree further. Each partial
arrangement loops over `n` columns, giving a conservative \(O(n \cdot n!)\)
time bound for the search, excluding the cost of constructing returned boards.
The mutable state and recursion stack use \(O(n)\) space, excluding the output.

## Pruning

Pruning stops a branch when no completion below it can be an answer. It changes
performance, not the set of candidates the algorithm intends to enumerate.
A pruning rule therefore needs a proof:

1. State what is already known about the partial candidate.
2. Show that every extension preserves the reason it cannot succeed.
3. Return before generating those extensions.

In N-Queens, an attacking pair cannot be repaired by placing more queens, so
the branch is permanently invalid. In a positive-number combination problem,
a sum above the target can only increase, so that branch may also be pruned.
The same sum rule would be unsound if negative numbers were still available.

Order candidates to expose impossible branches early when the order does not
change correctness. Sorting can also make duplicate choices adjacent, allowing
a loop to skip equal choices at the same depth. Be precise about the depth:
skipping every repeated value globally can remove valid answers that use the
same value at different positions.

## Common mistakes

1. **Missing restoration.** Every mutation made before recursion needs a
   matching inverse operation after recursion.
2. **Recording a mutable reference.** Store `path.copy()`, not `path`, when the
   current path is an answer.
3. **Using the wrong next state.** For subsets, recurse with `i + 1`, not
   `start + 1`; the next choices depend on the option just selected.
4. **Confusing a solution with a stopping point.** Some problems record every
   node, while others record only complete leaves. Decide this from the
   recursive contract.
5. **Unsound pruning.** Reject a branch only when no future choice can repair
   it. A condition that is currently false is not necessarily permanently
   false.
6. **Duplicate generation.** Define a canonical choice order or skip duplicate
   candidates at the same depth so that each answer has one path through the
   tree.

## Summary

Model the search as a decision tree and give each recursive call a precise
meaning. Maintain one partial candidate and enough auxiliary state to test the
next choice efficiently. For each valid choice, update the state, explore the
child, and restore the parent state exactly. Once that invariant is explicit,
recording answers, proving pruning rules, and avoiding duplicates become much
more mechanical.
