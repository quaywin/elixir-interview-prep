# ==============================================================================
# PRACTICAL EXERCISE DAY 1 (ADVANCED 4): ALGORITHMS IN FUNCTIONAL PROGRAMMING
# ==============================================================================
# This file contains 3 classic algorithm exercises solved using functional Elixir.
# You need to complete the logic in the TODO sections to pass the test suite.
#
# Exercise 1: Reverse Words in a Sentence (Reverse Words)
#   - Example: "the sky is blue" -> "blue is sky the"
#
# Exercise 2: Group Anagrams (Group Anagrams)
#   - Example: ["eat", "tea", "tan", "ate", "nat", "bat"]
#            -> [["ate", "eat", "tea"], ["nat", "tan"], ["bat"]]
#
# Exercise 3: Valid Parentheses (Valid Parentheses)
#   - Use a List as a Stack to check the validity of parentheses.
#   - Example: "()[]{}" -> true, "([)]" -> false
#
# Run this file with the command: elixir exercises/07_algorithms/algorithm_practice.exs
# ==============================================================================

defmodule ReverseWords do
  @doc """
  Takes a sentence string consisting of words separated by whitespace.
  Reverses the order of the words in the sentence (ignoring extra whitespace).

  Requirements: Do not use external libraries.
  Hints:
  - Use `String.split/1` to split words (which automatically removes extra whitespace).
  - Use either a tail-recursive function or an appropriate Enum pipeline.
  """
  def reverse(sentence) do
    # --- TODO: START WRITING YOUR CODE BELOW ---
    # Replace the line below with your code
    _sentence = sentence
    ""
  end
end

defmodule GroupAnagrams do
  @doc """
  Takes a list of words. Groups words that are anagrams of each other.
  (An anagram is a word formed by rearranging the letters of another).

  Hints:
  - For each word, sort its characters alphabetically to create a "representative key".
    Example: "eat" -> "aet", "tea" -> "aet".
  - Use `Enum.reduce/3` combined with a Map as a Hash Table to group words sharing the same representative key.
  - Use `Map.values/1` to extract the final list of results.
  """
  def group(words) do
    # --- TODO: START WRITING YOUR CODE BELOW ---
    # Replace the line below with your code
    _words = words
    []
  end
end

defmodule ValidParentheses do
  @doc """
  Takes a string containing only parentheses characters: '(', ')', '{', '}', '[', ']'.
  Checks whether the parentheses sequence is valid.

  Requirements: Use an Elixir List acting as a STACK data structure.
  - Iterate through each character of the string:
    - If it is an opening parenthesis: push (prepend) it onto the Stack.
    - If it is a closing parenthesis: match it with the top of the Stack. If matched, pop (remove) it from the Stack;
      if they do not match or the Stack is empty -> Return false.
  - Finally, if the Stack is empty, the string is valid (true), otherwise it is invalid (false).
  """
  def valid?(string) do
    # Convert string into a list of characters
    chars = String.codepoints(string)
    # Call the helper function running tail recursion with an initially empty Stack []
    check(chars, [])
  end

  # --- TODO: START WRITING RECURSIVE HELPER FUNCTIONS FOR EXERCISE 3 HERE ---
  # Hint: Define clauses of the check/2 function using pattern matching on head/tail.
  # (Example: defp check([], []), do: true)

  defp check(_chars, _stack) do
    # Replace with your recursive logic
    false
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule AlgorithmTest do
  use ExUnit.Case

  test "Exercise 1: Reverse Words" do
    assert ReverseWords.reverse("the sky is blue") == "blue is sky the"
    assert ReverseWords.reverse("  hello world!  ") == "world! hello"
    assert ReverseWords.reverse("a good   example") == "example good a"
  end

  test "Exercise 2: Group Anagrams" do
    input = ["eat", "tea", "tan", "ate", "nat", "bat"]
    output = GroupAnagrams.group(input)

    # Sort the results so that assertion is order-independent of the sublists
    sorted_output = output |> Enum.map(&Enum.sort/1) |> Enum.sort()

    expected = [
      ["ate", "eat", "tea"],
      ["nat", "tan"],
      ["bat"]
    ]

    sorted_expected = expected |> Enum.map(&Enum.sort/1) |> Enum.sort()

    assert sorted_output == sorted_expected
  end

  test "Exercise 3: Valid Parentheses" do
    assert ValidParentheses.valid?("()") == true
    assert ValidParentheses.valid?("()[]{}") == true
    assert ValidParentheses.valid?("(]") == false
    assert ValidParentheses.valid?("([)]") == false
    assert ValidParentheses.valid?("{[]}") == true
    assert ValidParentheses.valid?("]") == false
    assert ValidParentheses.valid?("(") == false
  end
end

# ==============================================================================
# INSTRUCTIONS / SUGGESTED ANSWERS (DO NOT DELETE THIS LINE SO YOU CAN REFER TO IT)
# ==============================================================================
#
# defmodule ReverseWords do
#   def reverse(sentence) do
#     sentence
#     |> String.split()
#     |> Enum.reverse()
#     |> Enum.join(" ")
#   end
# end
#
# defmodule GroupAnagrams do
#   def group(words) do
#     words
#     |> Enum.reduce(%{}, fn word, acc ->
#       key = word |> String.codepoints() |> Enum.sort() |> Enum.join()
#       Map.update(acc, key, [word], fn existing -> [word | existing] end)
#     end)
#     |> Map.values()
#   end
# end
#
# defmodule ValidParentheses do
#   def valid?(string) do
#     check(String.codepoints(string), [])
#   end
#
#   defp check([], []), do: true
#   defp check([], _stack), do: false
#   defp check([char | rest], stack) when char in ["(", "[", "{"] do
#     check(rest, [char | stack])
#   end
#   defp check([")" | rest], ["(" | stack_tail]), do: check(rest, stack_tail)
#   defp check(["]" | rest], ["[" | stack_tail]), do: check(rest, stack_tail)
#   defp check(["}" | rest], ["{" | stack_tail]), do: check(rest, stack_tail)
#   defp check(_chars, _stack), do: false
# end
