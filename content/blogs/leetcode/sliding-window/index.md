---
title: "Sliding Window"
weight: 8
date: 2026-08-11
draft: false
description: "How to enumerate contiguous ranges while maintaining a window invariant."
summary: "How to enumerate contiguous ranges while maintaining a window invariant."
tags: ["leetcode", "tech"]
---

> [!NOTE]- For those who come from Enumerate & Maintain
> Sliding window is an example of [Enumerate & Maintain]({{< ref "/blogs/leetcode/enumerate-and-maintain" >}}):
>
> - **Enumerate:** contiguous ranges.
> - **Maintain:** the state needed to evaluate the current range and restore its validity.
>
> Enumerate & Maintain is only a way to frame the problem. This article stands on its own, so feel free to skip this section.

## Principle

### Window, state, and invariant

A sliding-window algorithm examines contiguous subarrays or substrings. With
inclusive indices, the current window is the interval `seq[L:R + 1]`.

The **window** is the range itself. The **state** is the compact information we
store about that range, such as a frequency map or running sum. The
**invariant** is the statement that must be true about the window and its state
at a chosen point in the algorithm.

| Term | Example: longest substring without repeated characters |
| --- | --- |
| Window | The current substring `s[L:R + 1]` |
| State | `count[c]`, the number of occurrences of each character in the window |
| Invariant | After shrinking, every character has a count of at most one |

> [!IMPORTANT]
Do not treat the window and the invariant as the same thing. The window tells
us **which elements are selected**. The invariant tells us **what is known
about those elements**. A window can temporarily violate the invariant after
we add its next element; the algorithm then moves `L` until the invariant is
restored.

### Fixed-size and variable-size windows

There are two common forms:

1. **Fixed-size window:** the problem specifies a width `k`. The invariant is
   usually that the state represents exactly the `k` elements in the window.
2. **Variable-size window:** the range must satisfy a condition. After each
   expansion, shrink from `L` until the invariant is restored.

The variable-size pattern works when the validity condition is repairable by
removing elements from `L`. For example, "no duplicate characters" is
repairable: removing enough characters eventually removes the duplicate. Not
every subarray condition has this property.

## Templates

### Fixed-size window

Use this when every candidate has length `k`. The loop enumerates all such
windows, and `state` always describes `seq[L:R + 1]` when `record` runs.

```python
L = 0
state = make_empty_state()

for R, value in enumerate(seq):
    add(state, value)

    if R - L + 1 > k:
        remove(state, seq[L])
        L += 1

    if R - L + 1 == k:
        record(L, R, state)
```

### Variable-size window

Use this when validity controls the width. `record` executes only after the
state has again proved that the current window is valid.

```python
L = 0
state = make_empty_state()

for R, value in enumerate(seq):
    add(state, value)

    while not is_valid(state):
        remove(state, seq[L])
        L += 1

    record(L, R, state)
```

The invariant here is precise: immediately before `record`, `state` describes
`seq[L:R + 1]`, and that window is valid. `add` and `remove` must update
the same state, otherwise the invariant is no longer meaningful.

## Implementations

### Maximum sum with a fixed window

For a window of length `k`, the state can be one running sum. This implements
the fixed-size template without recomputing the sum for every range.

```python
def max_sum_of_length_k(nums: list[int], k: int) -> int:
    window_sum = 0
    best = float("-inf")
    L = 0

    for R, value in enumerate(nums):
        window_sum += value

        if R - L + 1 > k:
            window_sum -= nums[L]
            L += 1

        if R - L + 1 == k:
            best = max(best, window_sum)

    return best
```

After the subtraction, `window_sum` is the sum of
`nums[L:R + 1]`. The window length is controlled by the
boundary update; there is no validity-repair loop.

### Longest substring without repeating characters

For [LeetCode 3](https://leetcode.com/problems/longest-substring-without-repeating-characters/), the window is `s[L:R + 1]`. The state is a frequency map. The invariant after the `while` loop is that no character appears more than once.

```python
def length_of_longest_substring(s: str) -> int:
    count: dict[str, int] = {}
    L = 0
    best = 0

    for R, char in enumerate(s):
        count[char] = count.get(char, 0) + 1

        while count[char] > 1:
            removed = s[L]
            count[removed] -= 1
            L += 1

        best = max(best, R - L + 1)

    return best
```

When `char` creates a duplicate, the window becomes invalid. Moving `L`
does not search for a different kind of object; it removes elements from the
same window until the frequency map again proves that the window is valid.
For every `R`, the algorithm records the longest valid substring ending at
that index, which is enough to find the global maximum.

## Choosing the invariant

Before coding, write one sentence that can be checked after every update:

> `state` describes `seq[L:R + 1]`, and the window satisfies `valid(state)`.

Then decide which operation changes each part:

- Moving `R` adds one element to the window and state.
- Moving `L` removes one element from the window and state.
- The `while` loop exists only to restore validity after expansion.

This separation makes the template easier to adapt: change the state and
`valid` predicate for the problem, but keep the boundary-update discipline.
