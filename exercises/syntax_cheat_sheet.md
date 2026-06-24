# 📝 Cẩm Nang Tra Cứu Cú Pháp Nhanh (Elixir Syntax Cheat Sheet)

Sử dụng tài liệu này để copy-paste boilerplate hoặc tra cứu nhanh cấu trúc code khi đang làm bài tập hoặc phỏng vấn live coding.

---

## 1. Khung Xương GenServer Tiêu Chuẩn

```elixir
defmodule MyWorker do
  use GenServer, restart: :transient 
  # Tùy chọn restart:
  # - :permanent (mặc định, luôn restart khi die)
  # - :transient (chỉ restart nếu crash/lỗi, kết thúc bình thường :normal thì không restart)
  # - :temporary (không bao giờ restart dù crash hay không)

  # --- Client APIs (Chạy trên Process của caller) ---
  
  def start_link(init_arg) do
    # Khởi chạy process và liên kết (link) với parent process
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def get_data(pid) do
    # Đồng bộ (blocking), chờ phản hồi từ Server
    GenServer.call(pid, :get_data) 
  end

  def update_data(pid, new_val) do
    # Bất đồng bộ (non-blocking), gửi tin nhắn rồi đi tiếp ngay
    GenServer.cast(pid, {:update, new_val}) 
  end

  # --- Server Callbacks (Chạy bất đồng bộ trên Process của GenServer) ---

  @impl true
  def init(init_arg) do
    # Trả về {:ok, state} hoặc {:ok, state, {:continue, :post_init_step}} nếu có logic nặng/blocking
    {:ok, init_arg}
  end

  @impl true
  def handle_continue(:post_init_step, state) do
    # Thực hiện tác vụ nặng (như load DB, kết nối mạng) sau khi init đã boot xong tránh block parent process
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_data, _from, state) do
    # Trả về: {:reply, reply_value, new_state}
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:update, new_val}, _state) do
    # Trả về: {:noreply, new_state}
    {:noreply, new_val}
  end

  @impl true
  def handle_info(msg, state) do
    # Xử lý tin nhắn ngoài luồng (như timer, exit signals, tin nhắn từ process khác gửi bằng send/2)
    # Trả về: {:noreply, new_state}
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    # Dọn dẹp tài nguyên (đóng connection, lưu file...) trước khi die.
    # Chỉ chạy nếu process bị trap exit hoặc kết thúc tự nhiên (:normal)
    :ok
  end
end
```

---

## 2. Dynamic Process Management (Registry & DynamicSupervisor)

### 2.1. Đăng ký tên động qua Registry (Via Tuple)
```elixir
# Cấu trúc: {:via, Registry, {TênRegistry, KhóaUnique}}
def start_link(id) do
  name = {:via, Registry, {MyRegistry, id}}
  GenServer.start_link(__MODULE__, id, name: name)
end

# Gửi tin nhắn qua tên Registry thay vì PID
def get_data(id) do
  name = {:via, Registry, {MyRegistry, id}}
  GenServer.call(name, :get_data)
end
```

### 2.2. Tra cứu PID từ Registry
```elixir
case Registry.lookup(MyRegistry, "user_123") do
  [{pid, _value}] -> {:ok, pid}
  [] -> {:error, :not_found}
end
```

### 2.3. Khởi chạy & Tắt worker bằng DynamicSupervisor
```elixir
# 1. Định nghĩa DynamicSupervisor trong Module ứng dụng/Supervisor chính:
# {DynamicSupervisor, name: MyDynamicSupervisor, strategy: :one_for_one}

# 2. Khởi chạy worker động (nhận vào tuple {Module, arguments}):
{:ok, pid} = DynamicSupervisor.start_child(MyDynamicSupervisor, {MyWorker, "user_123"})

# 3. Tắt worker động an toàn (ngăn supervisor tự động restart nó):
:ok = DynamicSupervisor.terminate_child(MyDynamicSupervisor, pid)
```

---

## 3. Khung Xương Supervisor Tĩnh (Static Supervision Trees)

Rất cần khi thiết kế cấu trúc giám sát của hệ thống.

```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Khởi động Registry trước
      {Registry, keys: :unique, name: MyRegistry},
      
      # Khởi động DynamicSupervisor để quản lý worker động
      {DynamicSupervisor, name: MyDynamicSupervisor, strategy: :one_for_one},
      
      # Khởi động Task.Supervisor để quản lý các tác vụ bất đồng bộ
      {Task.Supervisor, name: MyTaskSupervisor},
      
      # Khởi động worker tĩnh thông thường
      {MyStaticWorker, arg: "hello"}
    ]

    # Các chiến lược (strategies):
    # - :one_for_one (Chỉ restart child bị die - phổ biến nhất)
    # - :one_for_all (Nếu 1 child die, restart TOÀN BỘ các children khác)
    # - :rest_for_one (Nếu 1 child die, restart các child định nghĩa SAU nó)
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

---

## 4. Quản lý Concurrency nâng cao (Task & Task.Supervisor)

Rất quan trọng cho các bài toán xử lý tác vụ bất đồng bộ giới hạn số lượng song song (`max_concurrency`).

### 4.1. Chạy song song không chặn (Fire and Forget)
```elixir
# Chạy bất đồng bộ, không quan tâm kết quả trả về
Task.start(fn -> 
  # logic... 
end)

# Chạy có giám sát (khuyên dùng trong production)
Task.Supervisor.start_child(MyTaskSupervisor, fn ->
  # logic...
end)
```

### 4.2. Chạy song song thu thập kết quả (Async-Await)
```elixir
# Khởi chạy các task song song
task1 = Task.async(fn -> do_some_work() end)
task2 = Task.async(fn -> do_other_work() end)

# Chờ và lấy kết quả (blocking ở đây)
result1 = Task.await(task1, 5000) # timeout mặc định là 5000ms
result2 = Task.await(task2, 5000)
```

### 4.3. Xử lý hàng loạt có giới hạn song song (Task.Supervisor.async_stream)
```elixir
# Rất tốt cho việc cào dữ liệu, xử lý file lớn cần giới hạn concurrency tránh tràn RAM
results = 
  items
  |> Task.Supervisor.async_stream(
    MyTaskSupervisor,
    fn item -> process_item(item) end,
    max_concurrency: 5, # Chỉ chạy tối đa 5 task song song tại một thời điểm
    timeout: 10_000,
    on_timeout: :kill_task # hoặc :ignore
  )
  |> Enum.to_list() # Trả về list dạng [{:ok, result}, {:error, reason}, ...]
```

---

## 5. Agent (Quản lý trạng thái đơn giản)

Agent là một lớp trừu tượng phía trên GenServer, cực kỳ hữu dụng để lưu trữ trạng thái đơn giản hoặc viết mock data trong lúc code test nhanh mà không muốn dựng cả GenServer phức tạp.

```elixir
# Khởi chạy Agent lưu trạng thái ban đầu là một Map
{:ok, agent_pid} = Agent.start_link(fn -> %{count: 0} end)

# Đọc trạng thái (Get)
count = Agent.get(agent_pid, fn state -> state.count end)

# Cập nhật trạng thái (Update)
Agent.update(agent_pid, fn state -> Map.put(state, :count, state.count + 1) end)

# Cập nhật và lấy kết quả trả về cùng lúc (Get & Update)
new_count = Agent.get_and_update(agent_pid, fn state ->
  new_val = state.count + 1
  # Định dạng trả về: {giá_trị_trả_về, trạng_thái_mới}
  {new_val, %{state | count: new_val}}
end)

# Dừng Agent
Agent.stop(agent_pid)
```

---

## 6. Thao tác Timer & ETS (Bộ nhớ đệm trong RAM)

### 6.1. Hẹn giờ gửi tin nhắn (Timer)
```elixir
# Gửi tin nhắn {:timeout, :job_expired} cho chính nó (self()) sau 3000ms
timer_ref = Process.send_after(self(), {:timeout, :job_expired}, 3000)

# Hủy timer (trả về số ms còn lại hoặc false nếu đã chạy xong)
Process.cancel_timer(timer_ref)
```

### 6.2. Khởi tạo & Thao tác bảng ETS
```elixir
# Khởi tạo bảng (chạy một lần duy nhất, thường ở init/1 của GenServer quản lý)
# Tùy chọn kiểu: :set (key duy nhất), :ordered_set, :bag (trùng key thoải mái), :duplicate_bag
# Quyền hạn: :protected (owner ghi, mọi người đọc), :public (mọi người đọc/ghi), :private (chỉ owner đọc/ghi)
# :named_table cho phép gọi bằng Atom tên bảng thay vì reference ID.
:ets.new(:my_cache, [:set, :protected, :named_table])

# Ghi dữ liệu: Định dạng là tuple, phần tử đầu tiên mặc định luôn là Key
:ets.insert(:my_cache, {key, val, extra_data})

# Đọc dữ liệu: Luôn trả về một list các tuples khớp key (kể cả :set)
case :ets.lookup(:my_cache, key) do
  [{^key, val, _extra}] -> {:ok, val}
  [] -> {:error, :not_found}
end

# Xóa bản ghi
:ets.delete(:my_cache, key)

# Tăng giá trị nguyên tử (Atomic Counter) - Rất quan trọng cho Rate Limiting!
# Tăng phần tử ở vị trí index 2 (1-based index) của tuple {key, count} lên 1 đơn vị
new_count = :ets.update_counter(:my_cache, key, {2, 1})
```

---

## 7. Cú Pháp Ecto & Quản Lý Transaction (`Ecto.Multi`)

### 7.1. Ecto Query Cơ Bản (Joins & Preloads)
```elixir
import Ecto.Query

# Query lọc, join và preload phức tạp hơn
query = 
  from p in Post,
    join: c in assoc(p, :comments),
    where: p.status == "published" and c.inserted_at > datetime_add(^DateTime.utc_now(), -1, "day"),
    order_by: [desc: p.inserted_at],
    preload: [comments: c],
    select: {p.title, c.body}

results = Repo.all(query)
```

### 7.2. Ecto Schema & Changeset Validation
```elixir
defmodule MyApp.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :age, :integer
    has_many :posts, MyApp.Post

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :age])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/@/)
    |> validate_number(:age, greater_than_or_equal_to: 18)
    |> unique_constraint(:email) # Check trùng ở DB level khi insert
  end
end
```

### 7.3. Ecto.Multi Pipeline (Thực thi chuỗi DB actions an toàn)
```elixir
alias Ecto.Multi

multi =
  Multi.new()
  # 1. Thêm một action insert/update struct có sẵn
  |> Multi.insert(:create_profile, %Profile{bio: "Hello"})
  
  # 2. Thêm một action tùy biến (nhận vào repo và kết quả các bước trước thông qua changes)
  |> Multi.run(:debit_account, fn repo, _changes ->
    case repo.get(Account, from_id) do
      nil -> {:error, :account_not_found}
      account ->
        # Xử lý logic...
        {:ok, updated_account}
    end
  end)
  
  # 3. Sử dụng kết quả của bước :debit_account trước đó
  |> Multi.run(:log_transaction, fn repo, %{debit_account: account} ->
    # log logic...
    {:ok, log_record}
  end)

# Thực thi thực tế
case Repo.transaction(multi) do
  {:ok, %{debit_account: acc, log_transaction: log}} ->
    # Thành công, trả về map chứa kết quả từng bước
    {:ok, acc}
    
  {:error, failed_step, failed_value, changes_so_far} ->
    # Thất bại, toàn bộ các bước trước đó đã được rollback tự động
    # failed_step sẽ là tên atom (như :debit_account) nơi xảy ra lỗi
    {:error, failed_step, failed_value}
end
```

---

## 8. Process Link, Monitor & Trap Exit (Xử lý lỗi OTP)

### 8.1. Monitor một Process khác (Một chiều)
```elixir
# Tạo giám sát một chiều. Nếu pid chết, process hiện tại sẽ nhận được tin nhắn {:DOWN, ...}
ref = Process.monitor(pid)

# Nhận tin nhắn DOWN trong handle_info/2
@impl true
def handle_info({:DOWN, ref, :process, pid, reason}, state) do
  IO.puts("Process #{inspect(pid)} died because of #{inspect(reason)}")
  {:noreply, state}
end
```

### 8.2. Trap Exit (Biến tín hiệu exit thành tin nhắn thường)
```elixir
# Chạy trong init/1 để ngăn process hiện tại bị chết lây khi linked process bị crash
Process.flag(:trap_exit, true)

# Nhận tin nhắn khi linked process chết
@impl true
def handle_info({:EXIT, dead_pid, reason}, state) do
  IO.puts("Linked process #{inspect(dead_pid)} exited with #{inspect(reason)}")
  {:noreply, state}
end
```

---

## 9. Thao Tác File & Thao Tác Lười (Streams)

Rất hữu ích khi đọc log file lớn hoặc xử lý dữ liệu dòng lớn.

### 9.1. Đọc/Ghi File cơ bản
```elixir
# Đọc toàn bộ file vào RAM
{:ok, content} = File.read("path/to/file.txt")

# Ghi đè file
:ok = File.write("path/to/file.txt", "content details")

# Ghi thêm vào cuối file (Append)
:ok = File.write("path/to/file.txt", "new log line\n", [:append])
```

### 9.2. Stream (Xử lý từng dòng file lười, không load hết vào RAM)
```elixir
# Đọc file, lọc dòng chứa lỗi, và lưu ra file mới một cách lười (lazy)
File.stream!("huge_development.log")
|> Stream.map(&String.trim/1)
|> Stream.filter(fn line -> String.contains?(line, "[ERROR]") end)
|> Stream.take(100) # Chỉ lấy 100 dòng lỗi đầu tiên
|> Stream.into(File.stream!("errors_only.log"))
|> Stream.run() # Bắt đầu thực thi thực tế
```

---

## 10. Thao Tác Map, List & Pattern Matching Điêu Luyện

### 10.1. Cập nhật Map lồng nhau (Nested Maps)
```elixir
# Dùng put_in để thay đổi giá trị theo đường dẫn khóa
new_map = put_in(map, [:user, :profile, :age], 30)

# Dùng update_in để tính toán giá trị mới dựa trên giá trị cũ
new_map = update_in(map, [:user, :profile, :age], fn age -> age + 1 end)
```

### 10.2. Gom nhóm/Tính toán bằng `Enum.reduce/3`
```elixir
# Tính tổng giá trị trong list
total = Enum.reduce([1, 2, 3], 0, fn num, acc -> num + acc end)

# Phân loại list thành Map gom nhóm
grouped = Enum.reduce(users, %{}, fn user, acc ->
  Map.update(acc, user.role, [user], fn list -> [user | list] end)
end)
```

### 10.3. Map.update/4 và Map.get_and_update/3
```elixir
# Map.update/4: Cập nhật key, nếu chưa có thì gán giá trị mặc định ban đầu
updated_map = Map.update(map, :counter, 1, fn current_val -> current_val + 1 end)

# Map.get_and_update/3: Vừa lấy giá trị cũ ra vừa cập nhật giá trị mới
{old_val, new_map} = Map.get_and_update(map, :status, fn
  nil -> {nil, "active"}
  current -> {current, "updated_" <> current}
end)
```

### 10.4. Pattern matching mạnh mẽ & Guard Clauses
```elixir
# Match cấu trúc Map phức tạp trực tiếp ở tham số hàm với Guards
def process_user(%{status: "active", profile: %{age: age}} = user) when age >= 18 and is_integer(age) do
  {:ok, :adult, user}
end
def process_user(_user), do: {:error, :unauthorized}
```

---

## 11. Xử lý Lỗi (Exceptions & try/catch)

```elixir
# 1. Custom Exception
defmodule MyApp.CustomError do
  defexception message: "something went wrong", details: nil
end

# Raise error
# raise MyApp.CustomError, message: "DB timeout"

# 2. Xử lý lỗi
try do
  # Code có thể sinh lỗi ở đây
  1 / 0
rescue
  e in ArithmeticError -> 
    IO.puts("Handled division by zero: #{e.message}")
  e in MyApp.CustomError ->
    IO.puts("Handled custom error: #{e.message}")
after
  # Luôn chạy (giống finally trong JS/Java)
  IO.puts("This always runs")
end
```

---

## 12. Erlang Interop (Gọi thư viện Erlang hữu dụng)

Erlang đi kèm các thư viện core cực mạnh, bạn có thể gọi trực tiếp từ Elixir.

### 12.1. Hash & Crypto (Sử dụng `:crypto`)
```elixir
# Tạo mã băm MD5 / SHA256
sha256_binary = :crypto.hash(:sha256, "my_secret_string")
hex_string = Base.encode16(sha256_binary, case: :lower) # Chuyển sang dạng string hex

# Tính toán HMAC (rất hay dùng cho ký token/signature)
hmac_binary = :crypto.mac(:hmac, :sha256, "my_secret_key", "data_to_sign")
```

### 12.2. Hàng đợi FIFO tối ưu (Sử dụng `:queue`)
Khi cần một hàng đợi Queue thực tế chạy cực nhanh, nhanh hơn nhiều việc append vào cuối List của Elixir.
```elixir
# Khởi tạo Queue rỗng
q = :queue.new()

# Thêm vào đuôi (In)
q = :queue.in("task1", q)
q = :queue.in("task2", q)

# Lấy ra từ đầu (Out)
case :queue.out(q) do
  {{:value, item}, remaining_q} -> 
    # item = "task1"
    {:ok, item, remaining_q}
  {:empty, _q} -> 
    {:error, :empty}
end
```

---

## 13. Telemetry (Phát tín hiệu giám sát hệ thống)

Dành cho các câu hỏi về Observability / Monitoring.

```elixir
# 1. Phát tán một event telemetry kèm metadata và số đo (measurements)
:telemetry.execute(
  [:my_app, :jobs, :complete], # Tên event (list atoms)
  %{duration: 120},            # Measurements (thường là thời gian chạy, số lượng...)
  %{job_id: "123", status: :ok} # Metadata
)

# 2. Lắng nghe event (thường config trong module Application start)
:ok = :telemetry.attach(
  "my-listener-id",            # Handler ID duy nhất
  [:my_app, :jobs, :complete], # Event cần lắng nghe
  &MyApp.TelemetryHandler.handle_event/4, # Callback function
  nil                          # config / state truyền thêm
)
```

---

## 14. Khung Xương Viết Unit Test (`ExUnit`)

Dùng để chạy test kiểm chứng code của bạn ngay trong buổi live coding.

```elixir
ExUnit.start()

defmodule MyPracticeTest do
  use ExUnit.Case, async: true

  # Cấu trúc setup để mock/khởi tạo trạng thái trước khi chạy test
  setup do
    # Bắt đầu Sandbox nếu test với Ecto Database
    # :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
    
    {:ok, db_conn: :connected, temp_user_id: "user_999"}
  end

  test "mô tả test case thành công", %{db_conn: conn, temp_user_id: user_id} do
    assert conn == :connected
    assert user_id == "user_999"
    refute 1 == 2 # refute ngược lại với assert (mong muốn kết quả false)
  end

  test "mô tả test case mong muốn lỗi" do
    assert_raise ArithmeticError, fn -> 1 / 0 end
  end
end
```
