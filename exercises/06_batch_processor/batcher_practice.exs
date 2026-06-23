# ==============================================================================
# BÀI TẬP THỰC HÀNH NÂNG CAO: BATCH PROCESSOR (CONCURRENCY & BATCHING)
# ==============================================================================
# Đề bài: Xây dựng một GenServer tên là `BatchProcessor` dùng để gom nhóm dữ liệu
# (ví dụ: log records hoặc database writes) và xử lý chúng theo lô (batch).
#
# Yêu cầu:
# 1. GenServer khởi chạy nhận tham số cấu hình:
#    - `batch_size`: Số lượng item tối đa trong một batch (ví dụ: 5 items).
#    - `timeout`: Thời gian tối đa (ms) chờ gom đủ batch trước khi tự động flush (ví dụ: 1000ms).
# 2. Định nghĩa API client:
#    - `add_item(item)`: Thêm một item bất đồng bộ vào batch (cast hoặc call).
#    - `flush()`: Chủ động yêu cầu flush các items hiện có bất kỳ lúc nào.
# 3. Khi gom đủ `batch_size` items HOẶC hết thời gian `timeout` mà chưa đủ batch,
#    GenServer phải gửi toàn bộ batch đó tới hàm xử lý `process_batch(items)`
#    và dọn dẹp queue trong state.
# 4. Sử dụng `:erlang.send_after/3` để quản lý timeout flush. Cần cẩn thận hủy timer cũ
#    nếu batch được flush sớm để tránh double-flush.
#
# Chạy file này bằng lệnh: elixir batcher_practice.exs
# ==============================================================================

defmodule BatchProcessor do
  use GenServer

  # --- CLIENT API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Thêm một item vào hàng đợi xử lý.
  """
  def add_item(item) do
    GenServer.call(__MODULE__, {:add_item, item})
  end

  @doc """
  Chủ động flush toàn bộ items hiện có trong queue để xử lý ngay lập tức.
  """
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(opts) do
    batch_size = Keyword.get(opts, :batch_size, 5)
    timeout = Keyword.get(opts, :timeout, 1000)
    callback = Keyword.get(opts, :callback, fn items -> IO.inspect(items, label: "Processed batch") end)

    state = %{
      batch_size: batch_size,
      timeout: timeout,
      callback: callback,
      queue: [],
      timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_item, item}, _from, state) do
    new_queue = state.queue ++ [item]

    if length(new_queue) >= state.batch_size do
      cancel_timer(state.timer)
      state.callback.(new_queue)
      {:reply, :ok, %{state | queue: [], timer: nil}}
    else
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
    cancel_timer(state.timer)
    if length(state.queue) > 0 do
      state.callback.(state.queue)
    end
    {:reply, :ok, %{state | queue: [], timer: nil}}
  end

  @impl true
  def handle_info(:timeout_flush, state) do
    if length(state.queue) > 0 do
      state.callback.(state.queue)
    end
    {:noreply, %{state | queue: [], timer: nil}}
  end

  # Helper để hủy timer an toàn
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: :erlang.cancel_timer(timer)
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule BatchProcessorTest do
  use ExUnit.Case
  @moduletag :capture_log

  setup do
    # Giả lập một test agent để kiểm tra xem các batch có được gửi đúng không
    {:ok, agent} = Agent.start_link(fn -> [] end)
    callback = fn items -> Agent.update(agent, fn state -> state ++ [items] end) end

    # Khởi động BatchProcessor với batch_size = 3 và timeout = 100ms
    start_supervised!({BatchProcessor, batch_size: 3, timeout: 100, callback: callback})
    
    {:ok, agent: agent}
  end

  test "gom đủ batch_size thì tự động xử lý và reset queue", %{agent: agent} do
    assert :ok = BatchProcessor.add_item("item_1")
    assert :ok = BatchProcessor.add_item("item_2")
    # Chưa đủ 3 items, callback chưa được gọi
    assert Agent.get(agent, & &1) == []

    assert :ok = BatchProcessor.add_item("item_3")
    # Đủ 3 items, callback phải được gọi
    assert Agent.get(agent, & &1) == [["item_1", "item_2", "item_3"]]
  end

  test "tự động flush sau khi hết thời gian timeout dù chưa đủ batch_size", %{agent: agent} do
    assert :ok = BatchProcessor.add_item("item_1")
    assert :ok = BatchProcessor.add_item("item_2")
    # Đợi 150ms (> timeout 100ms)
    Process.sleep(150)
    # Hệ thống phải tự động flush
    assert Agent.get(agent, & &1) == [["item_1", "item_2"]]
  end

  test "chủ động flush bằng client API", %{agent: agent} do
    assert :ok = BatchProcessor.add_item("item_1")
    assert :ok = BatchProcessor.flush()
    assert Agent.get(agent, & &1) == [["item_1"]]
  end
end
