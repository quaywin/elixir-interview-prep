# ==============================================================================
# BÀI TẬP THỰC HÀNH NGÀY 1 (NÂNG CAO 3): WRITE-THROUGH CACHE VỚI ETS & GENSERVER
# ==============================================================================
# Đề bài: Thiết kế một hệ thống Cache ghi-trực-tiếp (Write-Through Cache).
# Khách hàng có thể đọc dữ liệu cực nhanh song song từ bảng ETS mà không bị bottleneck.
# Nhưng các thao tác ghi dữ liệu bắt buộc phải gọi qua GenServer để đồng bộ
# ghi xuống Database (DB) và cập nhật lại bảng ETS.
#
# Yêu cầu:
# 1. Hệ thống gồm:
#    - Bảng ETS tên là `CacheTable` được khởi tạo dưới dạng `:set` và `:protected`.
#      GenServer `CacheService` đóng vai trò là Owner của bảng ETS này.
#    - Mẫu database giả lập bằng Agent (`MockDB`).
# 2. Định nghĩa API client trong `CacheService`:
#    - `read(key)`: ĐỌC TRỰC TIẾP từ bảng ETS `CacheTable` bằng `:ets.lookup/2`
#      trong context của caller process. Hoàn toàn KHÔNG dùng `GenServer.call` để tránh bottleneck.
#      Nếu cache hit -> trả về `{:ok, value}`.
#      Nếu cache miss -> trả về `{:error, :not_found}` (không cần tự động load từ DB ở đây).
#    - `write(key, value)`: GHI ĐỒNG BỘ bằng cách gửi `GenServer.call` tới `CacheService`.
# 3. Khi nhận lệnh `write(key, value)`, `CacheService` GenServer sẽ:
#    - Gọi ghi xuống DB giả lập (`MockDB.write(key, value)`).
#    - Nếu DB ghi thành công -> cập nhật key-value vào bảng ETS `CacheTable`.
#    - Trả về `:ok` cho caller.
#
# Chạy file này bằng lệnh: elixir write_through_cache_practice.exs
# ==============================================================================

# --- MOCK DATABASE ---
defmodule MockDB do
  use Agent

  def start_link(initial_state) when is_list(initial_state) do
    start_link(%{})
  end

  def start_link(initial_state) do
    Agent.start_link(fn -> initial_state end, name: __MODULE__)
  end

  def read(key) do
    Agent.get(__MODULE__, fn state -> Map.get(state, key) end)
  end

  def write(key, value) do
    # Giả lập thời gian ghi DB thực tế (slow I/O)
    Process.sleep(20)
    Agent.update(__MODULE__, fn state -> Map.put(state, key, value) end)
    :ok
  end
end

# --- CACHE SERVICE ---
defmodule CacheService do
  use GenServer

  @table_name :CacheTable

  # --- CLIENT API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Đọc dữ liệu cực nhanh từ cache.
  YÊU CẦU: Thao tác đọc phải chạy hoàn toàn đồng bộ trên caller process (ví dụ: HTTP Controller)
  bằng cách gọi trực tiếp vào bảng ETS. Không gửi message tới GenServer.
  """
  def read(key) do
    # Gọi :ets.lookup(@table_name, key)
    # Định dạng dữ liệu lưu trong ETS là {key, value}
    # Trả về:
    # - `{:ok, value}` nếu tìm thấy.
    # - `{:error, :not_found}` nếu không tìm thấy.
    case :ets.lookup(@table_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Ghi dữ liệu đồng bộ.
  YÊU CẦU: Giao dịch ghi phải đi qua GenServer để ghi xuống DB trước rồi mới cập nhật cache.
  """
  def write(key, value) do
    GenServer.call(__MODULE__, {:write, key, value})
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(_opts) do
    # Khởi tạo bảng ETS
    # YÊU CẦU: :set, :protected, :named_table (để dùng atom làm tên bảng)
    # :protected nghĩa là chỉ Owner process (GenServer này) được quyền ghi (write),
    # nhưng bất kỳ process nào khác cũng có quyền đọc (read).
    :ets.new(@table_name, [:set, :protected, :named_table])

    {:ok, %{}}
  end

  @impl true
  def handle_call({:write, key, value}, _from, state) do
    # 1. Ghi xuống Database giả lập
    case MockDB.write(key, value) do
      :ok ->
        # 2. Nếu ghi DB thành công, cập nhật vào ETS cache table
        # Định dạng lưu là tuple {key, value}
        :ets.insert(@table_name, {key, value})
        {:reply, :ok, state}
      _error ->
        {:reply, {:error, :db_write_failed}, state}
    end
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule WriteThroughCacheTest do
  use ExUnit.Case
  @moduletag :capture_log

  setup do
    # Khởi chạy Database giả lập với tham số map rỗng
    start_supervised!({MockDB, %{}})
    # Khởi chạy Cache Service
    start_supervised!(CacheService)
    :ok
  end

  test "đọc ghi dữ liệu đồng bộ và cập nhật cache thành công" do
    # Mới khởi tạo, cache phải rỗng
    assert {:error, :not_found} = CacheService.read("username")

    # Ghi dữ liệu thông qua Cache Service
    assert :ok = CacheService.write("username", "alice")

    # Đọc trực tiếp từ Cache (đọc nhanh từ ETS)
    assert {:ok, "alice"} = CacheService.read("username")

    # Dữ liệu phải được lưu xuống cả Database thực tế
    assert MockDB.read("username") == "alice"
  end

  test "các process khác nhau có thể đọc song song trực tiếp từ ETS" do
    # Ghi dữ liệu
    assert :ok = CacheService.write("session_token", "jwt_123456")

    # Spawn một process con độc lập và đọc cache từ process đó
    task = Task.async(fn ->
      CacheService.read("session_token")
    end)

    # Đảm bảo đọc thành công từ process con (nhờ cấu hình :protected của ETS)
    assert {:ok, "jwt_123456"} = Task.await(task)
  end

  test "đọc cache thất bại (cache miss) không tự động sửa DB" do
    # Ghi trực tiếp xuống DB, bypass qua Cache Service
    MockDB.write("bypass_key", "db_value")

    # Đọc từ cache service phải báo lỗi cache miss (vì không được ghi qua service)
    assert {:error, :not_found} = CacheService.read("bypass_key")
  end
end
