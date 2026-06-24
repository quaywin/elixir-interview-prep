# 💡 Elixir Algorithms Cookbook

For developers transitioning from OOP (such as Java, Python, Go) to Elixir, the biggest mistake when writing algorithms is attempting to apply "state-mutating loops" (imperative mutations). 

This document compiles the **core tricks** and **functional programming patterns** that will help you solve algorithmic problems optimally in Elixir.

---

## 1. Data Structure Tricks: Linked List vs Map

### 1.1. The Golden Rule of Lists in Elixir
In Elixir, a List (`[1, 2, 3]`) is structured as a **Singly Linked List**. Each element is a "cons cell" containing its value and a pointer to the next element.

*   **Never append (`list ++ [item]`) in a loop or recursion!**
    *   *Why:* To append an element to the end of a list of length $N$, the BEAM VM must traverse the list from beginning to end and copy all $N$ original cons cells. This has a complexity of **$O(N)$**. Doing this in a loop of $N$ iterations results in a total cost of **$O(N^2)$** -> Terrible performance.
    *   *Trick:* Always prepend to the head of the list using the cons syntax `[item | list]`, which has a cost of **$O(1)$**. Once the collection is complete, call `Enum.reverse/1` exactly once (cost is $O(N)$). The overall optimal complexity is **$O(N)$**.
*   **Do not access list elements by index (`Enum.at(list, index)`)**
    *   *Why:* Singly linked lists do not support random access. To get the $i$-th element, the BEAM must traverse $i$ elements from the start of the list (cost is $O(N)$).
    *   *Trick:* If the problem requires frequent random access by index (such as graphs or jump arrays), convert the list to a **Map** `{index => value}` or a **Tuple** (Tuples support $O(1)$ random access, but creating or modifying a tuple is expensive as it requires copying the entire tuple).

### 1.2. Using Map as a Hash Table ($O(1)$ Lookup)
When solving problems like Two Sum or Group Anagrams, you need extremely fast data lookup.
*   Under the hood, **Maps** in Elixir use a **HAMT (Hash Array Mapped Trie)** structure.
*   Looking up a key `Map.get(map, key)` or updating `Map.put(map, key, value)` has a complexity close to **$O(1)$** (strictly speaking, it is $O(\log N)$ with a very large branching factor, making it extremely fast).

---

## 2. Recursion Tricks: Body Recursion vs Tail Call Optimization (TCO)

Interviewers will evaluate whether you are at a Junior or Senior level based on how you design recursive functions.

### 2.1. Body Recursion
A recursive function that calls itself and leaves a pending operation (e.g., addition, multiplication) at the end.
```elixir
def sum([]), do: 0
def sum([head | tail]), do: head + sum(tail)  # Pending addition "+"
```
*   *Limitation:* The BEAM VM must store each function call in Stack Memory to await the result from the next recursive step before performing the addition. If the list has 1,000,000 elements, the stack will bloat to 1,000,000 frames -> Easily causing a **Stack Overflow** error.

### 2.2. Tail Recursion with an Accumulator
The final call of the function is to call itself, passing the accumulated state through an accumulator variable.
```elixir
def sum(list), do: do_sum(list, 0)

# Helper function implementing tail recursion
defp do_sum([], acc), do: acc
defp do_sum([head | tail], acc), do: do_sum(tail, acc + head) # The last call is the function invoking itself
```
*   *Optimization Mechanism:* The BEAM VM detects that there are no pending operations awaiting completion after the recursive call. It will **directly reuse the current stack frame (Tail Call Optimization - TCO)** and overwrite it with the new arguments. This keeps stack memory consumption constant at **$O(1)$**, making it completely safe for any data size.

---

## 3. Pattern Matching Tricks on Lists & Strings (Binary Matching)

One of Elixir's greatest strengths is its ability to perform deep pattern matching on binary and string structures.

### 3.1. Pattern Matching on Lists
Do not write code that checks if a list is empty or grabs the head using if/else:
```elixir
# Poor code style (Imperative)
def process(list) do
  if length(list) == 0 do
    :empty
  else
    head = hd(list)
    tail = tl(list)
    # logic...
  end
end

# Standard Elixir style (Functional)
def process([]), do: :empty
def process([head | tail]) do
  # logic directly using head and tail...
end
```

### 3.2. Fast Byte/String Reading with Binary Pattern Matching
If the problem requires string processing (e.g., parsing file formats, checking palindromes), you can match bytes/bits directly:
```elixir
# Extract the first UTF-8 character of the string
def parse_string(<<first_char::utf8, rest::binary>>) do
  IO.puts("First char: #{first_char}")
  parse_string(rest)
end
def parse_string(<<>>), do: :ok
```
*   *Trick:* Binary matching in the BEAM VM is optimized directly in underlying C code, running many times faster than using `String.split/2` or Regex to traverse strings.

---

## 4. Essential Enum Functions to Remember

Memorize the following functions to quickly solve problems without having to write recursion yourself:

1.  **`Enum.reduce(enumerable, acc, fun)`**:
    *   A versatile function to transform an enumerable into a single value (number, map, or another list).
2.  **`Enum.map_reduce(enumerable, acc, fun)`**:
    *   Transforms each element (map) while maintaining an accumulated state (reduce). Very useful for problems like calculating a running sum at each index.
3.  **`Enum.chunk_by(enumerable, fun)`**:
    *   Groups consecutive elements that satisfy a common condition.
4.  **`Enum.uniq(enumerable)`** or **`MapSet`**:
    *   Used to filter duplicate data. For $O(1)$ membership checks, populate a `MapSet` using `MapSet.new/1`.

---

## 5. Classic Algorithm Problem Template (Two Sum)

*   **Problem:** Given an array of integers `nums` and an integer `target`, return the indices of the two numbers such that they add up to `target`.
*   **Optimal FP Solution:** Traverse the array using a Map as a Hash Table to store `{number => index}` of visited numbers. For each number `x`, check if `target - x` already exists in the Map.

```elixir
defmodule TwoSum do
  def solve(nums, target) do
    # Convert list to include indices: [{val, idx}]
    nums
    |> Enum.with_index()
    # Search using reduce_while (allows early halt when the result is found)
    |> Enum.reduce_while(%{}, fn {val, idx}, seen ->
      complement = target - val
      
      case Map.fetch(seen, complement) do
        {:ok, prev_idx} ->
          # Found the matching pair, halt the loop and return indices
          {:halt, {prev_idx, idx}}
        :error ->
          # Not found yet, store the current number in the seen map and continue
          {:cont, Map.put(seen, val, idx)}
      end
    end)
  end
end
```
*   *Algorithm Complexity:*
    *   Time: **$O(N)$** (traverses the array only once; Map lookups take $O(1)$).
    *   Space: **$O(N)$** (uses a Map to store up to $N$ visited elements).
