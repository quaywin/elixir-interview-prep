# 💡 Cẩm Nang Thuật Toán Trong Lập Trình Hàm (Elixir Algorithms Cookbook)

Đối với các lập trình viên chuyển từ OOP (như Java, Python, Go) sang Elixir, sai lầm lớn nhất khi viết thuật toán là cố gắng áp dụng tư duy "vòng lặp thay đổi trạng thái" (imperative mutations). 

Tài liệu này tổng hợp các **mẹo cốt lõi (tricks)** và **mô hình tư duy lập trình hàm (functional patterns)** giúp bạn giải quyết các bài toán thuật toán tối ưu nhất trong Elixir.

---

## 1. Mẹo Cấu Trúc Dữ Liệu: Linked List vs Map

### 1.1. Quy tắc Vàng về List trong Elixir
Trong Elixir, List (`[1, 2, 3]`) được tổ chức dưới dạng **Single Linked List**. Mỗi phần tử là một "cons cell" chứa giá trị của nó và con trỏ trỏ tới phần tử tiếp theo.

*   **Không bao giờ append (`list ++ [item]`) trong vòng lặp hoặc đệ quy!**
    *   *Tại sao:* Để nối một phần tử vào cuối list dài $N$, BEAM VM bắt buộc phải duyệt từ đầu đến cuối list và copy lại toàn bộ $N$ cons cell cũ. Độ phức tạp là **$O(N)$**. Nếu lặp $N$ lần, tổng chi phí sẽ là **$O(N^2)$** -> Tệ hại.
    *   *Mẹo:* Luôn luôn thêm vào đầu list (prepend) bằng cú pháp cons `[item | list]` có chi phí **$O(1)$**. Khi hoàn thành việc thu thập kết quả, gọi `Enum.reverse/1` duy nhất một lần (chi phí $O(N)$). Tổng chi phí tối ưu là **$O(N)$**.
*   **Không truy cập phần tử theo index trong List (`Enum.at(list, index)`)**
    *   *Tại sao:* Linked list không hỗ trợ random access. Để lấy phần tử thứ $i$, BEAM phải đi qua $i$ phần tử từ đầu list (chi phí $O(N)$).
    *   *Mẹo:* Nếu bài toán yêu cầu truy cập ngẫu nhiên liên tục theo index (như đồ thị, mảng nhảy), hãy convert list sang **Map** `{index => value}` hoặc **Tuple** (Tuple hỗ trợ random access $O(1)$ nhưng chi phí tạo mới/thay đổi tuple rất đắt vì phải copy toàn bộ tuple).

### 1.2. Sử dụng Map làm Hash Table ($O(1)$ Lookup)
Khi giải bài toán như Two Sum, Group Anagrams, bạn cần tra cứu dữ liệu cực nhanh.
*   **Map** trong Elixir sử dụng cấu trúc **HAMT (Hash Array Mapped Trie)** dưới nền tảng.
*   Tra cứu khóa `Map.get(map, key)` hoặc cập nhật `Map.put(map, key, value)` có độ phức tạp gần như là **$O(1)$** (chính xác là $O(\log N)$ với cơ số rất lớn, hoạt động cực kỳ nhanh).

---

## 2. Mẹo Đệ Quy: Body Recursion vs Tail Call Optimization (TCO)

Interviewer sẽ đánh giá bạn ở mức Junior hay Senior dựa trên việc bạn thiết kế hàm đệ quy.

### 2.1. Đệ quy thân (Body Recursion)
Hàm đệ quy gọi chính nó và giữ lại một phép tính (ví dụ: cộng, nhân) ở cuối.
```elixir
def sum([]), do: 0
def sum([head | tail]), do: head + sum(tail)  # Giữ lại phép cộng "+"
```
*   *Hạn chế:* BEAM VM phải lưu trữ mỗi lượt gọi hàm vào Stack Memory để đợi kết quả trả về từ lượt đệ quy tiếp theo rồi mới thực hiện phép cộng. Nếu List có 1,000,000 phần tử, stack sẽ bị phình to 1,000,000 frame -> Dễ gây lỗi **Stack Overflow**.

### 2.2. Đệ quy đuôi (Tail Recursion) kết hợp Accumulator
Lượt gọi cuối cùng của hàm là gọi chính nó và chuyển trạng thái tích lũy qua biến nhận (accumulator).
```elixir
def sum(list), do: do_sum(list, 0)

# Hàm trợ giúp (Helper) thực thi đệ quy đuôi
defp do_sum([], acc), do: acc
defp do_sum([head | tail], acc), do: do_sum(tail, acc + head) # Lời gọi cuối cùng là gọi chính nó
```
*   *Cơ chế tối ưu:* BEAM VM nhận thấy không còn phép tính nào cần chờ xử lý sau lời gọi đệ quy. Nó sẽ **tái sử dụng trực tiếp khung stack hiện tại (Tail Call Optimization - TCO)** và ghi đè các tham số mới. Việc này giúp đệ quy tiêu tốn lượng bộ nhớ Stack cố định là **$O(1)$**, an toàn tuyệt đối với mọi kích thước dữ liệu.

---

## 3. Mẹo Pattern Matching trên Mảng & Chuỗi (Bi-Matching)

Một thế mạnh vượt trội của Elixir là khả năng pattern matching sâu trên cấu trúc nhị phân (binary/string).

### 3.1. Pattern matching trên List
Không viết code kiểm tra list rỗng hay lấy phần tử đầu bằng if/else:
```elixir
# Viết code xấu (Imperative)
def process(list) do
  if length(list) == 0 do
    :empty
  else
    head = hd(list)
    tail = tl(list)
    # logic...
  end
end

# Viết code chuẩn Elixir (Functional)
def process([]), do: :empty
def process([head | tail]) do
  # logic trực tiếp với head và tail...
end
```

### 3.2. Đọc byte/chuỗi nhanh với Binary Pattern Matching
Nếu bài toán yêu cầu xử lý chuỗi (ví dụ: parse định dạng file, kiểm tra chuỗi đối xứng), bạn có thể matching trực tiếp byte/bit:
```elixir
# Lấy ký tự đầu tiên dạng UTF-8 của chuỗi
def parse_string(<<first_char::utf8, rest::binary>>) do
  IO.puts("Ký tự đầu: #{first_char}")
  parse_string(rest)
end
def parse_string(<<>>), do: :ok
```
*   *Mẹo:* Binary matching của BEAM VM được tối ưu trực tiếp bằng mã C bên dưới, chạy nhanh gấp nhiều lần so với việc dùng `String.split/2` hayRegex để duyệt chuỗi.

---

## 4. Các Hàm Enum Cực Kỳ Quan Trọng Cần Ghi Nhớ

Hãy thuộc lòng các hàm sau để giải quyết nhanh các bài toán mà không cần tự viết đệ quy:

1.  **`Enum.reduce(enumerable, acc, fun)`**:
    *   Hàm vạn năng để biến đổi một danh sách thành một giá trị duy nhất (số, map, list khác).
2.  **`Enum.map_reduce(enumerable, acc, fun)`**:
    *   Vừa biến đổi từng phần tử (map), vừa duy trì một trạng thái tích lũy (reduce) đi kèm. Rất hữu ích khi giải bài toán dạng: tính tổng tích lũy tại từng vị trí index.
3.  **`Enum.chunk_by(enumerable, fun)`**:
    *   Gom nhóm các phần tử liên tiếp thỏa mãn chung một điều kiện.
4.  **`Enum.uniq(enumerable)`** hoặc **`MapSet`**:
    *   Khi cần lọc trùng dữ liệu. Để kiểm tra sự tồn tại trong $O(1)$, hãy đẩy dữ liệu vào `MapSet` bằng `MapSet.new/1`.

---

## 5. Mẫu Giải Bài Toán Thuật Toán Kinh Điển (Two Sum)

*   **Đề bài:** Cho mảng số nguyên `nums` và số nguyên `target`, tìm index của 2 số trong mảng có tổng bằng `target`.
*   **Giải pháp FP tối ưu:** Duyệt mảng, dùng một Map làm Hash Table lưu trữ `{number => index}` của các số đã đi qua. Với mỗi số `x`, kiểm tra xem `target - x` đã tồn tại trong Map chưa.

```elixir
defmodule TwoSum do
  def solve(nums, target) do
    # Convert list sang dạng có kèm index: [{val, idx}]
    nums
    |> Enum.with_index()
    # Tìm kiếm sử dụng reduce_while (cho phép dừng sớm khi tìm thấy kết quả)
    |> Enum.reduce_while(%{}, fn {val, idx}, seen ->
      complement = target - val
      
      case Map.fetch(seen, complement) do
        {:ok, prev_idx} ->
          # Tìm thấy cặp số thỏa mãn, dừng vòng lặp và trả về index
          {:halt, {prev_idx, idx}}
        :error ->
          # Chưa tìm thấy, lưu số hiện tại vào map seen và đi tiếp
          {:cont, Map.put(seen, val, idx)}
      end
    end)
  end
end
```
*   *Độ phức tạp thuật toán:*
    *   Thời gian: **$O(N)$** (chỉ duyệt mảng 1 lần, tìm kiếm trong Map mất $O(1)$).
    *   Không gian: **$O(N)$** (dùng Map lưu trữ tối đa $N$ phần tử đã đi qua).
