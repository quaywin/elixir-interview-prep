# ==============================================================================
# BÀI TẬP THỰC HÀNH NGÀY 2: GENSERVER RATE LIMITER
# ==============================================================================
# Đề bài: Xây dựng một GenServer tên là `RateLimiter` để giới hạn số lượng request
# từ mỗi IP.
# Yêu cầu:
# 1. GenServer khởi chạy nhận tham số cấu hình:
#    - `max_requests`: Số request tối đa được phép trong một chu kỳ (ví dụ: 5 request)
#    - `interval`: Độ dài chu kỳ tính bằng mili-giây (ví dụ: 5000ms = 5 giây)
# 2. Định nghĩa hàm API `request(ip)` gọi đồng bộ (handle_call) tới GenServer:
#    - Trả về `{:ok, current_count}` nếu IP đó chưa vượt quá giới hạn.
#    - Trả về `{:error, :rate_limited}` nếu IP đó đã vượt quá `max_requests`.
# 3. Phải tự động reset số lượng request (clear counters) của mỗi IP sau khi hết `interval`.
#    (Gợi ý: Dùng `:erlang.send_after/3` để gửi message định kỳ hoặc mỗi khi IP mới xuất hiện).
# 4. Viết các test case trong ExUnit để xác thực giải pháp.
#
# Chạy file này bằng lệnh: elixir rate_limiter_practice.exs
# ==============================================================================

defmodule RateLimiter do
  use GenServer

  # --- CLIENT API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gửi một request từ IP cụ thể.
  Trả về:
  - `{:ok, current_count}` nếu được chấp nhận.
  - `{:error, :rate_limited}` nếu vượt quá giới hạn.
  """
  def request(ip) do
    GenServer.call(__MODULE__, {:request, ip})
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(opts) do
    max_requests = Keyword.get(opts, :max_requests, 5)
    interval = Keyword.get(opts, :interval, 5000)

    state = %{
      max_requests: max_requests,
      interval: interval,
      ips: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:request, ip}, _from, state) do
    current_count = Map.get(state.ips, ip, 0)

    if current_count >= state.max_requests do
      {:reply, {:error, :rate_limited}, state}
    else
      new_count = current_count + 1
      new_ips = Map.put(state.ips, ip, new_count)

      # Nếu là request đầu tiên của IP này, thiết lập timer để reset IP
      if current_count == 0 do
        :erlang.send_after(state.interval, self(), {:reset_ip, ip})
      end

      {:reply, {:ok, new_count}, %{state | ips: new_ips}}
    end
  end

  @impl true
  def handle_info({:reset_ip, ip}, state) do
    new_ips = Map.delete(state.ips, ip)
    {:noreply, %{state | ips: new_ips}}
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule RateLimiterTest do
  use ExUnit.Case
  @moduletag :capture_log

  setup do
    # Khởi động RateLimiter với giới hạn 3 requests trong 200ms
    start_supervised!({RateLimiter, max_requests: 3, interval: 200})
    :ok
  end

  test "cho phép các request dưới hạn định" do
    assert {:ok, 1} = RateLimiter.request("192.168.1.1")
    assert {:ok, 2} = RateLimiter.request("192.168.1.1")
    assert {:ok, 3} = RateLimiter.request("192.168.1.1")
  end

  test "chặn request khi vượt quá giới hạn" do
    assert {:ok, 1} = RateLimiter.request("192.168.1.2")
    assert {:ok, 2} = RateLimiter.request("192.168.1.2")
    assert {:ok, 3} = RateLimiter.request("192.168.1.2")
    
    # Request thứ 4 phải bị chặn
    assert {:error, :rate_limited} = RateLimiter.request("192.168.1.2")
  end

  test "các IP khác nhau không ảnh hưởng tới hạn định của nhau" do
    assert {:ok, 1} = RateLimiter.request("192.168.1.3")
    assert {:ok, 1} = RateLimiter.request("10.0.0.1")
  end

  test "tự động reset giới hạn sau khoảng thời gian interval" do
    assert {:ok, 1} = RateLimiter.request("192.168.1.4")
    assert {:ok, 2} = RateLimiter.request("192.168.1.4")
    assert {:ok, 3} = RateLimiter.request("192.168.1.4")
    assert {:error, :rate_limited} = RateLimiter.request("192.168.1.4")

    # Đợi 250ms (interval là 200ms) để bộ đếm được reset
    Process.sleep(250)

    # Gửi lại thành công sau khi reset
    assert {:ok, 1} = RateLimiter.request("192.168.1.4")
  end
end
