---
title: "Binary Search"
weight: 6
date: 2026-08-10
draft: false
description: "A binary search template & illustration"
summary: "A binary search template & illustration"
tags: ["leetcode", "tech"]
---
{{< katex >}}

> [!NOTE]- For those who come from Enumerate & Maintain
> Binary search is an example of [enumerate and maintain]({{< ref "/blogs/leetcode/enumerate-and-maintain" >}}):
>
> - **Enumerate:** the remaining search interval.
> - **Maintain:** the monotonic predicate at its boundaries.
>
> Enumerate & Maintain is only a way to frame the problem. This article stands on its own, so feel free to skip this section.

## Principle
Binary search relies on a [monotonic](https://en.wikipedia.org/wiki/Monotonic_function) property. For a strictly increasing function \( f \),

$$
x_i < x_j \implies f(x_i) < f(x_j).
$$

Suppose we want to find \( x^* \) such that \( f(x^*) = t \), given an interval \( [\ell, r] \) that contains \( x^* \). Let

$$
m = \frac{\ell + r}{2}.
$$

The comparison between \( f(m) \) and \( t \) determines which half still contains \( x^* \):

$$
\begin{cases}
f(m) < t \implies m < x^* \implies x^* \in [m, r], \\
f(m) > t \implies m > x^* \implies x^* \in [\ell, m].
\end{cases}
$$

Thus, one iteration preserves the invariant \( x^* \in [\ell, r] \) by updating exactly one endpoint:

$$
\begin{cases}
\ell \gets m, & f(m) < t, \\
r \gets m, & f(m) > t.
\end{cases}
$$

> [!NOTE]
> The invariant guarantees that \( x^* \) remains inside the interval throughout the search.

## Implementation
The discussion above uses a continuous interval. In programming problems, binary search usually operates on discrete indices instead.

An interval may be open or closed at either endpoint:

1. \( (\ell, r) \)
2. \( [\ell, r] \)
3. \( [\ell, r) \)
4. \( (\ell, r] \)

This article uses an open interval. We initialize the universe as \( U = (-1,n) \), then set \( \ell = -1 \) and \( r = n \). The values \( \ell \) and \( r \) are virtual boundaries: treat \( \ell \) as passing and \( r \) as failing. At every step, \( (\ell,r) \) is the unchecked region.

```python
# seq = [...]
n = len(seq)
L = -1
R = n
while R - L > 1:
    m = (L + R) // 2
    if check(m):  # for example: f(seq, m) < t
        L = m
    else:
        R = m
```

The uppercase Python names are mutable boundaries, not constants. They are capitalized solely to make the left boundary distinct from the digit `1`; the mathematics uses conventional \( \ell \) and \( r \) instead.

For a concrete example, take `n = 5`. The virtual boundaries sit at `-1` and `n`, while the real indices are `0` through `4`. Initially every real index is unchecked; the midpoint is `2`.

{{< binary-search-axis
  labels="-1,0,1,2,3,4,n"
  states="pass,unchecked,unchecked,unchecked,unchecked,unchecked,fail"
  left="0"
  middle="3"
  right="6"
  caption="Initial partition: L = -1 passes, R = n fails, and m = 2 is checked next."
>}}

> [!TIP]
> Use `m = L + R >> 1` to type fast. In fixed-width integer languages, use `m = L + (R - L) // 2` to avoid overflow.

Let \( \operatorname{check}(i) \) denote the monotonic condition `f(seq, i) < t`. The invariant is

$$
\begin{aligned}
&\operatorname{check}(i) && \text{for every } i \in (-1,\ell], \\
&\neg\operatorname{check}(i) && \text{for every } i \in [r,n).
\end{aligned}
$$

The loop terminates with \( \ell + 1 = r \), at which point \( (\ell,r) \) contains no index. Then \( \ell \) is the last index for which \( f(\texttt{seq},\ell) < t \), unless \( \ell = -1 \), in which case no such index exists. Likewise, \( r \) is the first index for which \( f(\texttt{seq},r) \ge t \), unless \( r = n \), in which case no such index exists.

For a sorted sequence, this handles the boundary cases without special branches: if \( t \le f(\texttt{seq},0) \), then \( (\ell,r) = (-1,0) \); if \( t > f(\texttt{seq},n-1) \), then \( (\ell,r) = (n-1,n) \). For an empty sequence, \( n = 0 \) and the initial interval \( (-1,0) \) already satisfies the termination condition.

Equivalently, the open interval \( (\ell,r) \) contains every unchecked index, while the checked regions maintain:

1. \( -1 \le \ell < r \le n \).
2. Every index in \( (-1,\ell] \) passes `check`.
3. Every index in \( [r,n) \) fails `check`.

### Two updates

#### When the midpoint passes

Because \( m \in (\ell,r) \), we have \( \ell < m \). If `check(m)` passes, monotonicity implies that every index to its left also passes. Therefore, updating \( \ell \gets m \) extends the passing region from \( (-1,\ell] \) to \( (-1,m] \), while \( (m,r) \) becomes the new unchecked interval.

{{< binary-search-axis
  labels="-1,0,1,2,3,4,n"
  states="pass,pass,pass,pass,unchecked,unchecked,fail"
  left="3"
  right="6"
  caption="After check(2) passes: L moves to 2, so only indices 3 and 4 remain unchecked."
>}}

#### When the midpoint fails

Because \( m \in (\ell,r) \), we have \( m < r \). If `check(m)` fails, monotonicity implies that every index to its right also fails. Therefore, updating \( r \gets m \) extends the failing region from \( [r,n) \) to \( [m,n) \), while \( (\ell,m) \) becomes the new unchecked interval.

{{< binary-search-axis
  labels="-1,0,1,2,3,4,n"
  states="pass,unchecked,unchecked,fail,fail,fail,fail"
  left="0"
  right="3"
  caption="After check(2) fails: R moves to 2, so only indices 0 and 1 remain unchecked."
>}}

More generally, `check` may be any monotonic condition whose passing indices form a prefix. Each iteration maintains:

1. \( (-1,\ell] \) **passes** `check`.
2. \( [r,n) \) **fails** `check`.
3. \( (\ell,r) \) contains the unchecked candidates.

## Why the search terminates
While \( r - \ell > 1 \), the midpoint

$$
m = \left\lfloor\frac{\ell + r}{2}\right\rfloor
$$

satisfies \( \ell < m < r \). Thus, either update makes the open interval strictly smaller while preserving \( \ell < r \). When the loop stops, \( r - \ell \le 1 \). Since \( \ell < r \) and both endpoints are integers,

$$
0 < r-\ell \le 1,
$$

so \( r - \ell = 1 \), or equivalently \( \ell + 1 = r \).

## Why use an open interval

The open interval is the unchecked region, not the entire partition. Since \( \ell \) is known to pass and \( r \) is known to fail, the complete partition is

$$
\begin{aligned}
U &= (-1,\ell] \cup (\ell,r) \cup [r,n), \\
U \setminus (\ell,r) &= (-1,\ell] \cup [r,n).
\end{aligned}
$$

Thus, \( (-1,\ell] \) passes, \( (\ell,r) \) remains unchecked, and \( [r,n) \) fails. The closed endpoints in the checked regions are necessary: they record the outcomes at the current boundaries \( \ell \) and \( r \).

The advantage of the open convention is that the *unchecked* region is always \( (\ell,r) \). After either update, it remains \( (\ell,r) \) with one boundary replaced, so no \( \ell + 1 \), \( r - 1 \), or endpoint-conversion bookkeeping is needed to describe the next search interval.

## Example: Search Insert Position

[LeetCode 35: Search Insert Position](https://leetcode.com/problems/search-insert-position/) asks for the index of `target` in a sorted array, or the index where it should be inserted to keep the array sorted. This is exactly the first index whose value is not less than `target`.

Use the template with

$$
\operatorname{check}(i) \iff \texttt{nums[i] < target}.
$$

Then `L` finishes at the last index with a smaller value and `R` finishes at the first index with `nums[R] >= target`. The latter is the required answer, including when the target is absent.

```python
class Solution:
    def searchInsert(self, nums: list[int], target: int) -> int:
        L = -1
        R = len(nums)

        while R - L > 1:
            m = (L + R) // 2
            if nums[m] < target:
                L = m
            else:
                R = m

        return R
```

For `nums = [1, 3, 5, 6]`, the function returns `2` for `target = 5`, `1` for `target = 2`, and `4` for `target = 7`. The virtual failing boundary at `n` makes the final case work without a special branch. Each iteration halves the unchecked interval, so the time complexity is \(O(\log n)\) and the algorithm uses \(O(1)\) extra space.
