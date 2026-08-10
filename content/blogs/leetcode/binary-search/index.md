---
title: "Binary Search"
weight: 6
date: 2026-08-10
draft: false
description: "A binary search template & illustration"
tags: ["leetcode", "tech"]
---
{{< katex >}}
## Principle
Binary search relies on a [monotonic](https://en.wikipedia.org/wiki/Monotonic_function) property. For a strictly increasing function \( f \),

$$
x_i < x_j \implies f(x_i) < f(x_j).
$$

Suppose we want to find \( x^* \) such that \( f(x^*) = t \), given an interval \( [l, r] \) that contains \( x^* \). Let

$$
m = \frac{l + r}{2}.
$$

The comparison between \( f(m) \) and \( t \) determines which half still contains \( x^* \):

$$
\begin{cases}
f(m) < t \implies m < x^* \implies x^* \in [m, r], \\
f(m) > t \implies m > x^* \implies x^* \in [l, m].
\end{cases}
$$

Thus, one iteration preserves the invariant \( x^* \in [l, r] \) by updating exactly one endpoint:

$$
\begin{cases}
l \gets m, & f(m) < t, \\
r \gets m, & f(m) > t.
\end{cases}
$$

> [!NOTE]
> The invariant guarantees that \( x^* \) remains inside the interval throughout the search.

## Implementation
The discussion above uses a continuous interval. In programming problems, binary search usually operates on discrete indices instead.

An interval may be open or closed at either endpoint:

1. \( (l, r) \)
2. \( [l, r] \)
3. \( [l, r) \)
4. \( (l, r] \)

This article uses an open interval. We initialize the universe as \( U = (-1,n) \), then set \( l = -1 \) and \( r = n \). The values \( l \) and \( r \) are virtual boundaries: treat \( l \) as passing and \( r \) as failing. At every step, \( (l,r) \) is the unchecked region.

```python
# seq = [...]
n = len(seq)
l = -1
r = n
while r - l > 1:
    m = (l + r) // 2
    if check(m):  # for example: f(seq, m) < t
        l = m
    else:
        r = m
```

Let \( \operatorname{check}(i) \) denote the monotonic condition `f(seq, i) < t`. The invariant is

$$
\begin{aligned}
&\operatorname{check}(i) && \text{for every } i \in (-1,l], \\
&\neg\operatorname{check}(i) && \text{for every } i \in [r,n).
\end{aligned}
$$

The loop terminates with \( l + 1 = r \), at which point \( (l,r) \) contains no index. If \( r < n \), then \( r \) is the first index for which \( f(\texttt{seq},r) \ge t \); otherwise, no such index exists.

Equivalently, the open interval \( (l,r) \) contains every unchecked index, while the checked regions maintain:

1. \( -1 \le l < r \le n \).
2. Every index in \( (-1,l] \) passes `check`.
3. Every index in \( [r,n) \) fails `check`.

### Two updates

#### When the midpoint passes

Because \( m \in (l,r) \), we have \( l < m \). If `check(m)` passes, monotonicity implies that every index to its left also passes. Therefore, updating \( l \gets m \) extends the passing region from \( (-1,l] \) to \( (-1,m] \), while \( (m,r) \) becomes the new unchecked interval.

#### When the midpoint fails

Because \( m \in (l,r) \), we have \( m < r \). If `check(m)` fails, monotonicity implies that every index to its right also fails. Therefore, updating \( r \gets m \) extends the failing region from \( [r,n) \) to \( [m,n) \), while \( (l,m) \) becomes the new unchecked interval.

More generally, `check` may be any monotonic condition whose passing indices form a prefix. Each iteration maintains:

1. \( (-1,l] \) **passes** `check`.
2. \( [r,n) \) **fails** `check`.
3. \( (l,r) \) contains the unchecked candidates.

## Why the search terminates
While \( r - l > 1 \), the midpoint

$$
m = \left\lfloor\frac{l + r}{2}\right\rfloor
$$

satisfies \( l < m < r \). Thus, either update makes the open interval strictly smaller while preserving \( l < r \). When the loop stops, \( r - l \le 1 \). Since \( l < r \) and both endpoints are integers,

$$
0 < r-l \le 1,
$$

so \( r - l = 1 \), or equivalently \( l + 1 = r \).

## Why use an open interval

The open interval is the unchecked region, not the entire partition. Since \( l \) is known to pass and \( r \) is known to fail, the complete partition is

$$
\begin{aligned}
U &= (-1,l] \cup (l,r) \cup [r,n), \\
U \setminus (l,r) &= (-1,l] \cup [r,n).
\end{aligned}
$$

Thus, \( (-1,l] \) passes, \( (l,r) \) remains unchecked, and \( [r,n) \) fails. The closed endpoints in the checked regions are necessary: they record the outcomes at the current boundaries \( l \) and \( r \).

The advantage of the open convention is that the *unchecked* region is always \( (l,r) \). After either update, it remains \( (l,r) \) with one boundary replaced, so no \( l + 1 \), \( r - 1 \), or endpoint-conversion bookkeeping is needed to describe the next search interval.
