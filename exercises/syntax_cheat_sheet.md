# 📝 Cẩm Nang Tra Cứu Cú Pháp Nhanh (Elixir Syntax Cheat Sheet)

Sử dụng tài liệu này để xem nhanh cấu trúc code khi đang làm bài tập hoặc ôn tập phản xạ nhanh.

---

## 1. Khung Xương GenServer Tiêu Chuẩn

```elixir
defmodule MyWorker do
  use GenServer, restart: :transient # :permanent (mặc định), :transient (chỉ restart nếu crash), :temporary (không bao giờ restart)

  # --- Client APIs ---
  
  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def get_data do
    GenServer.call(__MODULE__, :get_data) # Đồng bộ (blocking)
  end

  def update_data(new_val) do
    GenServer.cast(__MODULE__, {:update, new_val}) # Bất đồng bộ (non-blocking)
  end

  # --- Server Callbacks ---

  @impl true
  def init(init_arg) do
    # Trả về {:ok, state} hoặc {:ok, state, {:continue, :post_init_step}} nếu có logic nặng
    {:ok, init_arg}
  end

  @impl true
  def handle_continue(:post_init_step, state) do
    # Logic nặng xử lý ở đây sau khi process đã boot xong
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_data, _from, state) do
    # Trả về: {:reply, reply_value, new_state}
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:update, new_val}, state) do
    # Trả về: {:noreply, new_state}
    {:noreply, new_val}
  end

  @impl true
  def handle_info(msg, state) do
    # Xử lý tin nhắn ngoài luồng (như timer, exit signals)
    # Trả về: {:noreply, new_state}
    {:noreply, state}
  end
end
```

---

## 2. Quản Lý Process Động (Registry & DynamicSupervisor)

### 2.1. Đăng ký Via Tuple (Registry)
```elixir
# Cấu trúc: {:via, Registry, {TênRegistry, KhóaUnique}}
name_tuple = {:via, Registry, {UserRegistry, "user_123"}}

# Khởi chạy process với tên động
GenServer.start_link(__MODULE__, arg, name: name_tuple)
```

### 2.2. Tra cứu PID từ Registry
```elixir
case Registry.lookup(UserRegistry, "user_123") do
  [{pid, _value}] -> {:ok, pid}
  [] -> {:error, :not_found}
end
```

### 2.3. Khởi chạy & Tắt worker bằng DynamicSupervisor
```elixir
# Khởi chạy worker mới động
{:ok, pid} = DynamicSupervisor.start_child(MyDynamicSupervisor, {MyWorker, "user_123"})

# Tắt worker động an toàn (không bị supervisor tự restart)
:ok = DynamicSupervisor.terminate_child(MyDynamicSupervisor, pid)
```

---

## 3. Thao tác Timer & ETS (Erlang Engine)

### 3.1. Hẹn giờ gửi tin nhắn (Non-blocking Timer)
```elixir
# Gửi tin nhắn {:reset, "user_123"} cho chính nó (self()) sau 5000ms
timer_ref = :erlang.send_after(5000, self(), {:reset, "user_123"})

# Hủy timer hẹn giờ
:erlang.cancel_timer(timer_ref)
```

### 3.2. Khởi tạo & Thao tác bảng ETS
```elixir
# Khởi tạo bảng (thường chạy trong init/1 của GenServer owner)
# Tùy chọn: :set (key độc nhất), :ordered_set, :bag (trùng key khác val), :duplicate_bag
# Quyền: :protected (owner ghi, mọi người đọc), :public (mọi người đọc ghi), :private (chỉ owner đọc ghi)
:ets.new(:MyTable, [:set, :protected, :named_table])

# Ghi dữ liệu (định dạng tuple, phần tử đầu tiên mặc định là key)
:ets.insert(:MyTable, {key, value})

# Đọc dữ liệu (luôn trả về một list các tuples khớp key)
case :ets.lookup(:MyTable, key) do
  [{^key, value}] -> {:ok, value}
  [] -> {:error, :not_found}
end
```

---

## 4. Pipeline Ecto.Multi Tiêu Chuẩn

```elixir
Ecto.Multi.new()
|> Ecto.Multi.run(:debit, fn repo, _changes ->
  case repo.get(Account, from_id) do
    nil -> {:error, :not_found}
    account ->
      # thực hiện ghi...
      {:ok, updated_account}
  end
end)
|> Ecto.Multi.run(:credit, fn repo, changes ->
  # Truy cập kết quả của bước :debit trước đó thông qua changes.debit
  _debit_result = changes.debit
  {:ok, credit_result}
end)
|> Repo.transaction() # Thực thi thực tế
```
