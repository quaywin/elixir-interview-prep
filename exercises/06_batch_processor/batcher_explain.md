# 💡 Giải Thích Bài Tập: Batch Processor (`GenServer` & `Timer` & `Cancellation`)

## 1. Yêu Cầu Thực Tế & Thiết Kế
Trong các hệ thống logging (như gửi telemetry metrics, ghi audit log, push data sang ElasticSearch), việc ghi từng bản ghi một xuống đĩa cứng hoặc gọi API bên ngoài cho mỗi request sẽ tạo ra lượng tải IOPS cực lớn và latency cao.
Phương án tối ưu là **Batching (Gom nhóm)** dữ liệu: Gom đủ 100 items hoặc đợi tối đa 1 giây mới ghi một lần.

**Yêu cầu thiết kế:**
*   Một GenServer `BatchProcessor` nhận các item và lưu tạm vào list `state.queue`.
*   Nếu kích thước queue đạt tới `batch_size` -> Gọi callback ghi dữ liệu ngay lập tức.
*   Nếu chưa đủ `batch_size` nhưng hết thời gian `timeout` -> Tự động kích hoạt flush lượng dữ liệu hiện có.
*   **Điểm mấu chốt (Senior Level):** Nếu dữ liệu được flush sớm do gom đủ `batch_size` trước khi hết giờ, bắt buộc phải hủy timer cũ đi. Nếu không, khi timer cũ hết giờ, nó sẽ gửi tin nhắn flush lần hai, gây lỗi logic hoặc gửi các lô dữ liệu trống.

---

## 2. Giải Thích Code Triển Khai

```elixir
defmodule BatchProcessor do
  use GenServer

  # ... Client API ...

  @impl true
  def handle_call({:add_item, item}, _from, state) do
    new_queue = state.queue ++ [item]

    if length(new_queue) >= state.batch_size do
      # ĐỦ BATCH SIZE: Flush ngay
      # 1. Hủy bỏ timer hẹn giờ cũ (nếu có)
      cancel_timer(state.timer)
      
      # 2. Xử lý dữ liệu
      state.callback.(new_queue)
      
      # 3. Reset queue và timer
      {:reply, :ok, %{state | queue: [], timer: nil}}
    else
      # CHƯA ĐỦ BATCH SIZE: Đợi thêm
      # 4. Nếu chưa có timer nào chạy, khởi tạo timer mới
      timer = if is_nil(state.timer) do
        :erlang.send_after(state.timeout, self(), :timeout_flush)
      else
        state.timer
      end
      
      {:reply, :ok, %{state | queue: new_queue, timer: timer}}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    # CHỦ ĐỘNG FLUSH QUA API
    cancel_timer(state.timer)
    if length(state.queue) > 0 do
      state.callback.(state.queue)
    end
    {:reply, :ok, %{state | queue: [], timer: nil}}
  end

  @impl true
  def handle_info(:timeout_flush, state) do
    # FLUSH DO HẾT GIỜ (TIMEOUT)
    if length(state.queue) > 0 do
      state.callback.(state.queue)
    end
    {:noreply, %{state | queue: [], timer: nil}}
  end

  # Helper hủy timer an toàn
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: :erlang.cancel_timer(timer)
end
```

---

## 3. Các Điểm Quan Trọng Dưới Góc Nhìn Kỹ Thuật

### 3.1. Hủy Timer An Toàn (`:erlang.cancel_timer/1`)
*   Khi `:erlang.send_after/3` được gọi, nó trả về một kiểu dữ liệu tham chiếu (Reference).
*   Nếu chúng ta không gọi `:erlang.cancel_timer(timer)`, tin nhắn `:timeout_flush` chắc chắn vẫn sẽ được đẩy vào mailbox của GenServer khi hết giờ.
*   *Lưu ý về Race Condition:* Đôi khi, bạn gọi `cancel_timer(timer)` đúng lúc tin nhắn `:timeout_flush` vừa kịp bay vào Mailbox của GenServer trước đó một vài micro-giây. Để an toàn tuyệt đối, trong hàm `handle_info(:timeout_flush)`, chúng ta kiểm tra điều kiện `if length(state.queue) > 0`. Nếu queue đã được dọn sạch trước đó bởi một cú flush sớm, chúng ta chỉ việc bỏ qua không làm gì cả, tránh việc gửi batch rỗng tới callback.

### 3.2. Hiệu Năng Phép Cộng List (`state.queue ++ [item]`)
*   Trong lập trình hàm, cấu trúc List là Single Linked List. Phép toán `list ++ [item]` (thêm vào cuối) có độ phức tạp thuật toán là $O(N)$ vì nó phải duyệt qua toàn bộ các phần tử hiện tại để tạo ra list mới.
*   Nếu `batch_size` lớn (ví dụ: 10,000 items), việc gọi liên tục `list ++ [item]` sẽ làm sụt giảm nghiêm trọng hiệu năng CPU do liên tục cấp phát lại vùng nhớ.
*   *Giải pháp tối ưu hơn:* Thêm phần tử vào đầu list bằng toán tử cons: `new_queue = [item | state.queue]` có chi phí $O(1)$. Khi thực hiện flush, ta chỉ cần đảo ngược danh sách lại một lần duy nhất bằng hàm `:lists.reverse(new_queue)` (hoặc `Enum.reverse/1`) trước khi gửi sang callback.
