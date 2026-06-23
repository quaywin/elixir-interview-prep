# ==============================================================================
# BÀI TẬP THỰC HÀNH NÂNG CAO: DYNAMIC PROCESS MANAGEMENT (REGISTRY & DYNAMICSUPERVISOR)
# ==============================================================================
# Đề bài: Xây dựng hệ thống quản lý session đăng nhập của người dùng.
# Mỗi khi user đăng nhập, hệ thống sẽ khởi chạy một GenServer đại diện cho session đó
# để lưu trữ các thông tin tạm thời (ví dụ: giỏ hàng, token) in-memory.
#
# Yêu cầu:
# 1. Sử dụng Registry để đăng ký tên động cho mỗi session process dưới dạng:
#    `{:via, Registry, {UserRegistry, user_id}}`
# 2. Sử dụng DynamicSupervisor để giám sát và khởi chạy các session process động.
# 3. Định nghĩa module `SessionWorker` (GenServer) lưu trữ state của session.
# 4. Định nghĩa module `SessionManager` cung cấp các API:
#    - `start_session(user_id)`: Khởi chạy session mới.
#    - `get_session_data(user_id)`: Lấy dữ liệu session hiện tại.
#    - `update_session_data(user_id, key, value)`: Cập nhật dữ liệu session.
#    - `stop_session(user_id)`: Tắt session process khi user logout.
#
# Chạy file này bằng lệnh: elixir session_manager_practice.exs
# ==============================================================================

defmodule SessionWorker do
  use GenServer, restart: :transient

  # Helper để sinh định danh via tuple dùng cho Registry
  def via_tuple(user_id) do
    {:via, Registry, {UserRegistry, user_id}}
  end

  # --- CLIENT API ---

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, %{}, name: via_tuple(user_id))
  end

  def get_data(pid) do
    GenServer.call(pid, :get_data)
  end

  def put_data(pid, key, value) do
    GenServer.call(pid, {:put_data, key, value})
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(initial_state) do
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_data, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:put_data, key, value}, _from, state) do
    new_state = Map.put(state, key, value)
    {:reply, :ok, new_state}
  end
end

defmodule SessionManager do
  @doc """
  Khởi chạy một SessionWorker mới dưới DynamicSupervisor (tên là UserSessionSupervisor).
  Nếu session đã tồn tại cho user_id này, trả về `{:error, :already_started}`.
  """
  def start_session(user_id) do
    case DynamicSupervisor.start_child(UserSessionSupervisor, {SessionWorker, user_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lấy dữ liệu state hiện tại của session từ user_id.
  Nếu session không tồn tại, trả về `{:error, :not_found}`.
  """
  def get_session_data(user_id) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> {:ok, SessionWorker.get_data(pid)}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Cập nhật dữ liệu của session từ user_id.
  Nếu session không tồn tại, trả về `{:error, :not_found}`.
  """
  def update_session_data(user_id, key, value) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> {:ok, SessionWorker.put_data(pid, key, value)}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Tắt session process khi user logout.
  """
  def stop_session(user_id) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> 
        DynamicSupervisor.terminate_child(UserSessionSupervisor, pid)
        :ok
      [] -> {:error, :not_found}
    end
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule SessionManagerTest do
  use ExUnit.Case

  setup do
    # Khởi động Registry và DynamicSupervisor dùng riêng cho test
    start_supervised!({Registry, keys: :unique, name: UserRegistry})
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: UserSessionSupervisor})
    :ok
  end

  test "khởi tạo session thành công và lấy dữ liệu trống ban đầu" do
    assert {:ok, pid} = SessionManager.start_session("user_123")
    assert is_pid(pid)

    assert {:ok, data} = SessionManager.get_session_data("user_123")
    assert data == %{}
  end

  test "không cho phép tạo trùng session cho cùng 1 user" do
    assert {:ok, _pid} = SessionManager.start_session("user_123")
    assert {:error, :already_started} = SessionManager.start_session("user_123")
  end

  test "cập nhật và lấy dữ liệu session thành công" do
    assert {:ok, _pid} = SessionManager.start_session("user_456")
    assert {:ok, :ok} = SessionManager.update_session_data("user_456", :cart, ["item_1", "item_2"])
    assert {:ok, data} = SessionManager.get_session_data("user_456")
    assert data == %{cart: ["item_1", "item_2"]}
  end

  test "trả về error khi thao tác trên session không tồn tại" do
    assert {:error, :not_found} = SessionManager.get_session_data("non_existent")
    assert {:error, :not_found} = SessionManager.update_session_data("non_existent", :key, "val")
  end

  test "dừng session thành công (logout) và giải phóng process" do
    assert {:ok, _pid} = SessionManager.start_session("user_789")
    assert :ok = SessionManager.stop_session("user_789")
    # Session không còn tồn tại nữa
    assert {:error, :not_found} = SessionManager.get_session_data("user_789")
  end
end
