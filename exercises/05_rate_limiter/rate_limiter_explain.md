# 💡 Giải Thích Bài Tập: Rate Limiter (`GenServer` & `Timer`)

## 1. Yêu Cầu Thực Tế & Thiết Kế
Rate Limiter (Bộ giới hạn tần suất) là thành phần bắt buộc trong các ứng dụng Web/APIs công cộng để chống tấn công DDoS, bảo vệ tài nguyên hệ thống khỏi bị cạn kiệt, hoặc giới hạn lưu lượng sử dụng của từng gói tài khoản (API Quota).

**Yêu cầu thiết kế:**
*   Một GenServer tập trung quản lý bộ đếm số request của từng IP.
*   Nếu số request của 1 IP vượt quá `max_requests` trong vòng `interval` mili-giây, chặn các request tiếp theo của IP đó.
*   Cần tự động dọn dẹp bộ đếm (reset) cho mỗi IP khi hết chu kỳ `interval` để tránh việc bộ nhớ RAM tăng lên vô hạn do lưu trữ dữ liệu IP rác.

---

## 2. Giải Thích Code Triển Khai

```elixir
defmodule RateLimiter do
  use GenServer

  # ... Client API ...

  @impl true
  def handle_call({:request, ip}, _from, state) do
    # 1. Lấy số request hiện tại của IP trong Map state.ips (mặc định là 0)
    current_count = Map.get(state.ips, ip, 0)

    if current_count >= state.max_requests do
      # 2. Vượt ngưỡng -> Từ chối request, giữ nguyên state
      {:reply, {:error, :rate_limited}, state}
    else
      new_count = current_count + 1
      new_ips = Map.put(state.ips, ip, new_count)

      # 3. Kỹ thuật Reset Timer:
      # Nếu đây là request đầu tiên của IP này trong chu kỳ hiện tại (count = 0)
      if current_count == 0 do
        # Đăng ký một timer gửi tin nhắn bất đồng bộ :reset_ip cho chính nó sau `state.interval` ms
        :erlang.send_after(state.interval, self(), {:reset_ip, ip})
      end

      {:reply, {:ok, new_count}, %{state | ips: new_ips}}
    end
  end

  @impl true
  def handle_info({:reset_ip, ip}, state) do
    # 4. Khi timer kích hoạt -> Xóa IP khỏi map bộ đếm để giải phóng RAM
    new_ips = Map.delete(state.ips, ip)
    {:noreply, %{state | ips: new_ips}}
  end
end
```

---

## 3. Các Điểm Quan Trọng Dưới Góc Nhìn Kỹ Thuật

### 3.1. Tại sao dùng `:erlang.send_after/3` thay vì `Process.sleep/1`?
*   `Process.sleep/1` sẽ block hoàn toàn process hiện tại. Nếu bạn sleep 5 giây trong GenServer, nó sẽ đứng im không thể nhận bất kỳ request nào khác của các IP khác, làm sập toàn bộ hệ thống API.
*   `:erlang.send_after/3` là cơ chế **không chặn (non-blocking)**. Nó đăng ký một sự kiện hẹn giờ trực tiếp với Erlang Run-time System (ERTS). ERTS sẽ tự động đẩy một tin nhắn `{:reset_ip, ip}` vào mailbox của GenServer khi hết thời gian, trong khi GenServer vẫn tiếp tục nhận các request khác bình thường.

### 3.2. Tiết Kiệm Bộ Nhớ (Memory Overhead)
*   Nếu chúng ta không xóa IP ra khỏi map `state.ips` khi hết chu kỳ, sau một vài ngày hoạt động với hàng triệu IP khách vãng lai, Map này sẽ phình to ra hàng Gigabytes bộ nhớ RAM.
*   Gọi `Map.delete(state.ips, ip)` khi hết chu kỳ giúp đảm bảo bộ nhớ của GenServer luôn được giải phóng kịp thời, chỉ lưu trữ thông tin của các IP đang hoạt động tích cực trong vòng vài giây gần nhất.

### 3.3. Hạn Chế Của Giải Pháp Slide Window (Cửa sổ trượt)
*   Giải pháp trên áp dụng thuật toán **Fixed Window (Cửa sổ cố định)**: Reset bộ đếm đúng $T$ mili-giây kể từ request đầu tiên.
*   *Lược đồ lỗi (Failure Mode):* Nếu giới hạn là 100 requests/phút. User có thể gửi 100 requests ở giây thứ 59, và tiếp tục gửi 100 requests ở giây thứ 61 (ngay sau khi reset). Kết quả là user đã gửi 200 requests chỉ trong 2 giây mà không bị chặn.
*   *Giải pháp Senior hơn:* Sử dụng thuật toán **Token Bucket** hoặc **Leaky Bucket** (sử dụng Redis sorted sets hoặc thư viện như `ExRated` / `Hammer` trong môi trường distributed thực tế).
