---
title: "Recursive Algorithm"
weight: 6
date: 2026-08-10
draft: false
description: "A practical way to design, prove, and analyze recursive algorithms"
summary: "A practical way to design, prove, and analyze recursive algorithms"
tags: ["leetcode", "tech"]
---
{{< katex >}}

## Principle

A recursive algorithm solves a problem by reducing it to one or more smaller instances of the same problem. Its correctness follows the same structure as [mathematical induction](https://en.wikipedia.org/wiki/Mathematical_induction):

1. **Base case.** Prove that the answer is correct for the smallest valid input.
2. **Inductive step.** Assume the recursive call returns a correct answer for every smaller input, then show how to use those answers to solve the current input.

If every call eventually reaches a base case, these two facts establish correctness for every valid input size.

For example, let \(P(n)\) mean: "`solve(n)` returns the correct answer for an input of size \(n\)." We prove \(P(0)\), then prove that \(P(k)\) implies \(P(k+1)\). The recursive call is not a mystery; during the inductive step, treat it as a black box that already solves its smaller subproblem correctly.

> [!NOTE]
> Correctness and termination are separate obligations. A recurrence can describe the right answer and still recurse forever if no argument moves toward a base case.

## Implementation

Before writing code, define the **recursive contract**. It should say exactly what the function receives and exactly what it returns. A useful contract is small enough that every recursive call is obviously the same kind of problem, just smaller.

Then follow this workflow:

1. **Design \(P(n)\).** State what `solve(...)` returns for its parameters. Include any boundaries, indices, or accumulated state in the definition.
2. **Solve the base case.** Return the answer directly for the smallest input, or for an empty/invalid range when that is more natural.
3. **Reduce the problem.** Express the current answer using recursive calls on strictly smaller subproblems.

The code shape is usually:

```python
def solve(problem):
    if is_base_case(problem):
        return base_answer(problem)

    smaller_problems = reduce(problem)
    smaller_answers = [solve(p) for p in smaller_problems]
    return combine(problem, smaller_answers)
```

The names `reduce` and `combine` matter more than the syntax. `reduce` must make measurable progress, such as shortening an interval, removing one element, or moving down one tree level. `combine` must explain how correct answers for the smaller instances produce the correct answer for the current instance.

### A proof checklist

For every recursive function, answer these questions before trusting it:

1. What does one call promise to return?
2. Which inputs stop immediately, and is their returned value correct?
3. Why is each recursive call a valid smaller instance of that promise?
4. Why does combining the returned values solve the current instance?
5. What quantity decreases on every path, guaranteeing that a base case is reached?

> [!IMPORTANT]
> When deriving the transition, assume the recursive call works. Do not expand its implementation in your head. Your job at one level is only to define the current answer from smaller correct answers.

## Example: Fibonacci number

Consider [LeetCode 509: Fibonacci Number](https://leetcode.com/problems/fibonacci-number/). It is a compact example because the recurrence is given directly:

$$
F(n) =
\begin{cases}
0, & n = 0, \\
1, & n = 1, \\
F(n-1) + F(n-2), & n \ge 2.
\end{cases}
$$

{{< tree-diagram
  nodes="fib(4),fib(3),fib(2),fib(2),fib(1),fib(1),fib(0)"
  highlight="2,3"
  caption="A call tree for fib(4). Both highlighted nodes solve the same fib(2) subproblem, which is why memoization helps."
>}}

Define \(P(n)\) as: `fib(n)` returns \(F(n)\). The base cases return \(0\) and \(1\). For \(n \ge 2\), `fib(n - 1)` and `fib(n - 2)` are calls on smaller inputs; assuming they return the correct Fibonacci numbers, their sum is \(F(n)\).

```python
def fib(n: int) -> int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)
```

The argument decreases on every call, so termination is immediate. However, this direct implementation recomputes the same values many times. Its recurrence is approximately

$$
T(n) = T(n-1) + T(n-2) + O(1),
$$

which is exponential. Memoization preserves the recursive contract while evaluating each `fib(k)` once:

```python
from functools import cache


@cache
def fib(n: int) -> int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)
```

Now the time complexity is \(O(n)\), and the cache plus recursion stack use \(O(n)\) space.

## Example: Build a binary tree

Consider [LeetCode 105: Construct Binary Tree from Preorder and Inorder Traversal](https://leetcode.com/problems/construct-binary-tree-from-preorder-and-inorder-traversal/). This problem is harder because the recursive contract must carry enough context to identify a subtree.

Let `build(left, right)` return the binary tree whose inorder traversal is `inorder[left:right]`. The interval is half-open, so `left == right` represents an empty tree. A shared `preorder_index` points to the next root not yet consumed.

The first unused preorder value is the root of the current subtree. Its position `mid` in the inorder traversal divides the subtree into two smaller subtrees:

$$
\text{left subtree} = [\text{left}, \text{mid}), \qquad
\text{right subtree} = [\text{mid}+1, \text{right}).
$$

{{< tree-diagram
  nodes="3,9,20,-,-,15,7"
  caption="The binary tree reconstructed from preorder = [3, 9, 20, 15, 7] and inorder = [9, 3, 15, 20, 7]. A dash represents an absent child."
>}}

```python
class Solution:
    def buildTree(self, preorder: list[int], inorder: list[int]) -> TreeNode | None:
        position = {value: i for i, value in enumerate(inorder)}
        preorder_index = 0

        def build(left: int, right: int) -> TreeNode | None:
            nonlocal preorder_index

            if left == right:
                return None

            root_value = preorder[preorder_index]
            preorder_index += 1
            root = TreeNode(root_value)

            mid = position[root_value]
            root.left = build(left, mid)
            root.right = build(mid + 1, right)
            return root

        return build(0, len(inorder))
```

The contract supplies the proof:

1. **Base case:** an empty inorder interval contains no nodes, so returning `None` is correct.
2. **Inductive step:** the next preorder value is the root of the current subtree. Its inorder position splits the remaining nodes into exactly the left and right subtrees. By the contract, the two recursive calls build those subtrees correctly; attaching them to the root builds the current tree correctly.
3. **Termination:** each call receives a strictly shorter inorder interval. Therefore every path reaches an empty interval.

Building `position` costs \(O(n)\). Each node is created once and each recursive call does \(O(1)\) work beyond its children, so the total time is \(O(n)\). The map and the recursion stack use \(O(n)\) space in the worst case.

## Common mistakes

1. **An ambiguous contract.** A function named `dfs(node)` is not enough. Decide whether it returns a height, a Boolean, a path, or modifies shared state before writing the transition.
2. **No progress.** Calling `solve(n)` from `solve(n)` without changing the state never reaches the base case.
3. **Wrong base value.** The empty input often has a meaningful identity value: `0` for a sum, `1` for a product or count of empty choices, and `None` for an empty tree.
4. **Overlapping subproblems.** If different branches compute the same state, memoize by the complete state, not by only part of it.
5. **Stack depth.** A recursion of depth \(n\) can exceed the language runtime's stack limit. When a problem can be deeply skewed, an iterative solution or an explicit stack may be safer.

## Summary

Recursion becomes routine once every call has a precise promise. Define that promise, answer its smallest instance, reduce the current instance to smaller calls, and combine their correct answers. Finally, verify that every call moves toward a base case and analyze whether repeated states require memoization.
