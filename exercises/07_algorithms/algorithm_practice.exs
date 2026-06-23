# ==============================================================================
# BÀI TẬP THỰC HÀNH NGÀY 1 (NÂNG CAO 4): THUẬT TOÁN BẰNG LẬP TRÌNH HÀM
# ==============================================================================
# File này chứa 3 bài tập thuật toán kinh điển được giải bằng lập trình hàm Elixir.
# Bạn cần hoàn thành logic ở các phần TODO để vượt qua bộ test suite.
#
# Bài 1: Đảo ngược chuỗi từ (Reverse Words)
#   - Ví dụ: "the sky is blue" -> "blue is sky the"
#
# Bài 2: Nhóm từ đảo đối xứng (Group Anagrams)
#   - Ví dụ: ["eat", "tea", "tan", "ate", "nat", "bat"]
#            -> [["ate", "eat", "tea"], ["nat", "tan"], ["bat"]]
#
# Bài 3: Kiểm tra đóng mở ngoặc hợp lệ (Valid Parentheses)
#   - Sử dụng List làm Stack để kiểm tra tính hợp lệ của ngoặc.
#   - Ví dụ: "()[]{}" -> true, "([)]" -> false
#
# Chạy file này bằng lệnh: elixir exercises/07_algorithms/algorithm_practice.exs
# ==============================================================================

defmodule ReverseWords do
  @doc """
  Nhận vào một chuỗi câu gồm các từ cách nhau bởi khoảng trắng.
  Đảo ngược thứ tự các từ trong câu đó (bỏ qua khoảng trắng thừa).
  
  Yêu cầu: Không sử dụng các thư viện ngoài.
  Gợi ý:
  - Dùng `String.split/1` để tách từ (tự động loại bỏ khoảng trắng thừa).
  - Sử dụng phép toán đệ quy đuôi hoặc pipeline Enum phù hợp.
  """
  def reverse(sentence) do
    # --- TODO: BẮT ĐẦU VIẾT CODE CỦA BẠN DƯỚI ĐÂY ---
    # Thay thế dòng dưới bằng code của bạn
    _sentence = sentence
    ""
  end
end

defmodule GroupAnagrams do
  @doc """
  Nhận vào một list các từ. Nhóm các từ là anagram của nhau lại với nhau.
  (Anagram là các từ được tạo ra bằng cách sắp xếp lại các ký tự của nhau).
  
  Gợi ý:
  - Với mỗi từ, hãy sắp xếp các ký tự của nó theo bảng chữ cái để tạo ra "key đại diện".
    Ví dụ: "eat" -> "aet", "tea" -> "aet".
  - Dùng `Enum.reduce/3` kết hợp với một Map làm Hash Table để nhóm các từ có chung key đại diện.
  - Sử dụng `Map.values/1` để lấy ra danh sách kết quả cuối cùng.
  """
  def group(words) do
    # --- TODO: BẮT ĐẦU VIẾT CODE CỦA BẠN DƯỚI ĐÂY ---
    # Thay thế dòng dưới bằng code của bạn
    _words = words
    []
  end
end

defmodule ValidParentheses do
  @doc """
  Nhận vào một chuỗi chỉ chứa các ký tự ngoặc: '(', ')', '{', '}', '[', ']'.
  Kiểm tra xem chuỗi đóng mở ngoặc có hợp lệ hay không.
  
  Yêu cầu: Sử dụng List của Elixir hoạt động như cấu trúc dữ liệu STACK (ngăn xếp).
  - Duyệt qua từng ký tự của chuỗi:
    - Nếu là ngoặc mở: đẩy (prepend) vào Stack.
    - Nếu là ngoặc đóng: so khớp với phần tử đầu Stack. Nếu khớp thì pop (loại bỏ) khỏi Stack,
      nếu không khớp hoặc Stack rỗng -> Trả về false.
  - Cuối cùng, nếu Stack rỗng thì chuỗi hợp lệ (true), ngược lại là không hợp lệ (false).
  """
  def valid?(string) do
    # Convert string thành list các ký tự
    chars = String.codepoints(string)
    # Gọi hàm helper chạy đệ quy đuôi với Stack ban đầu là rỗng []
    check(chars, [])
  end

  # --- TODO: BẮT ĐẦU VIẾT CÁC HÀM HELPER ĐỆ QUY CHO BÀI 3 TẠI ĐÂY ---
  # Gợi ý: Định nghĩa các clause của hàm check/2 sử dụng pattern matching trên head/tail.
  # (Ví dụ: defp check([], []), do: true)
  
  defp check(_chars, _stack) do
    # Thay thế bằng logic đệ quy của bạn
    false
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule AlgorithmTest do
  use ExUnit.Case

  test "Bài 1: Đảo ngược chuỗi từ" do
    assert ReverseWords.reverse("the sky is blue") == "blue is sky the"
    assert ReverseWords.reverse("  hello world!  ") == "world! hello"
    assert ReverseWords.reverse("a good   example") == "example good a"
  end

  test "Bài 2: Nhóm từ đảo đối xứng (Anagrams)" do
    input = ["eat", "tea", "tan", "ate", "nat", "bat"]
    output = GroupAnagrams.group(input)
    
    # Sắp xếp lại kết quả để so khớp không phụ thuộc thứ tự các list con
    sorted_output = output |> Enum.map(&Enum.sort/1) |> Enum.sort()
    
    expected = [
      ["ate", "eat", "tea"],
      ["nat", "tan"],
      ["bat"]
    ]
    sorted_expected = expected |> Enum.map(&Enum.sort/1) |> Enum.sort()

    assert sorted_output == sorted_expected
  end

  test "Bài 3: Kiểm tra ngoặc hợp lệ" do
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
# HƯỚNG DẪN / ĐÁP ÁN GỢI Ý (ĐỪNG XÓA DÒNG NÀY ĐỂ BẠN CÓ THỂ XEM KHI CẦN)
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
