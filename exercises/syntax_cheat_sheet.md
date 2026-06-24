# 📝 Elixir Syntax Cheat Sheet (Cẩm Nang Tra Cứu Cú Pháp Nhanh)

Use this document to copy-paste boilerplate or quickly look up code structures when doing exercises or during live coding interviews.

---

## 1. Standard GenServer Skeleton

```elixir
defmodule MyWorker do
  use GenServer, restart: :transient 
  # Restart options:
  # - :permanent (default, always restarts when it dies)
  # - :transient (restarts only if it crashes/errors; does not restart on normal termination :normal)
  # - :temporary (never restarts, whether it crashes or not)

  # --- Client APIs (Runs on the caller's process) ---
  
  def start_link(init_arg) do
    # Starts the process and links it to the parent process
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def get_data(pid) do
    # Synchronous (blocking), waits for response from the Server
    GenServer.call(pid, :get_data) 
  end

  def update_data(pid, new_val) do
    # Asynchronous (non-blocking), sends the message and continues immediately
    GenServer.cast(pid, {:update, new_val}) 
  end

  # --- Server Callbacks (Runs asynchronously on the GenServer's process) ---

  @impl true
  def init(init_arg) do
    # Returns {:ok, state} or {:ok, state, {:continue, :post_init_step}} if there is heavy/blocking logic
    {:ok, init_arg}
  end

  @impl true
  def handle_continue(:post_init_step, state) do
    # Performs heavy tasks (like loading DB, network connection) after init has finished booting, to avoid blocking the parent process
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_data, _from, state) do
    # Returns: {:reply, reply_value, new_state}
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:update, new_val}, _state) do
    # Returns: {:noreply, new_state}
    {:noreply, new_val}
  end

  @impl true
  def handle_info(msg, state) do
    # Handles out-of-band messages (like timers, exit signals, messages sent from other processes via send/2)
    # Returns: {:noreply, new_state}
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    # Cleans up resources (closing connections, saving files...) before dying.
    # Only runs if the process traps exits or terminates naturally (:normal)
    :ok
  end
end
```

---

## 2. Dynamic Process Management (Registry & DynamicSupervisor)

### 2.1. Dynamic registration via Registry (Via Tuple)
```elixir
# Structure: {:via, Registry, {RegistryName, UniqueKey}}
def start_link(id) do
  name = {:via, Registry, {MyRegistry, id}}
  GenServer.start_link(__MODULE__, id, name: name)
end

# Send message using the Registry name instead of PID
def get_data(id) do
  name = {:via, Registry, {MyRegistry, id}}
  GenServer.call(name, :get_data)
end
```

### 2.2. Looking up PID from Registry
```elixir
case Registry.lookup(MyRegistry, "user_123") do
  [{pid, _value}] -> {:ok, pid}
  [] -> {:error, :not_found}
end
```

### 2.3. Starting & Stopping workers using DynamicSupervisor
```elixir
# 1. Define DynamicSupervisor in the Application Module/Main Supervisor:
# {DynamicSupervisor, name: MyDynamicSupervisor, strategy: :one_for_one}

# 2. Start dynamic worker (takes a tuple of {Module, arguments}):
{:ok, pid} = DynamicSupervisor.start_child(MyDynamicSupervisor, {MyWorker, "user_123"})

# 3. Stop dynamic worker safely (prevents the supervisor from automatically restarting it):
:ok = DynamicSupervisor.terminate_child(MyDynamicSupervisor, pid)
```

---

## 3. Static Supervision Trees Skeleton

Crucial when designing the supervision structure of the system.

```elixir
defmodule MyApp.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Start Registry first
      {Registry, keys: :unique, name: MyRegistry},
      
      # Start DynamicSupervisor to manage dynamic workers
      {DynamicSupervisor, name: MyDynamicSupervisor, strategy: :one_for_one},
      
      # Start Task.Supervisor to manage asynchronous tasks
      {Task.Supervisor, name: MyTaskSupervisor},
      
      # Start a regular static worker
      {MyStaticWorker, arg: "hello"}
    ]

    # Strategies:
    # - :one_for_one (Only restart the child that died - most common)
    # - :one_for_all (If 1 child dies, restart ALL other children)
    # - :rest_for_one (If 1 child dies, restart children defined AFTER it)
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

---

## 4. Advanced Concurrency Management (Task & Task.Supervisor)

Very important for tasks involving asynchronous processing with concurrency limits (`max_concurrency`).

### 4.1. Non-blocking parallel execution (Fire and Forget)
```elixir
# Run asynchronously, result is ignored
Task.start(fn -> 
  # logic... 
end)

# Supervised execution (recommended in production)
Task.Supervisor.start_child(MyTaskSupervisor, fn ->
  # logic...
end)
```

### 4.2. Parallel execution with result collection (Async-Await)
```elixir
# Start tasks in parallel
task1 = Task.async(fn -> do_some_work() end)
task2 = Task.async(fn -> do_other_work() end)

# Wait and retrieve the result (blocking here)
result1 = Task.await(task1, 5000) # default timeout is 5000ms
result2 = Task.await(task2, 5000)
```

### 4.3. Batch processing with concurrency limits (Task.Supervisor.async_stream)
```elixir
# Great for web scraping, processing large files where limiting concurrency is needed to avoid running out of RAM
results = 
  items
  |> Task.Supervisor.async_stream(
    MyTaskSupervisor,
    fn item -> process_item(item) end,
    max_concurrency: 5, # Only run at most 5 tasks in parallel at a time
    timeout: 10_000,
    on_timeout: :kill_task # or :ignore
  )
  |> Enum.to_list() # Returns a list of type [{:ok, result}, {:error, reason}, ...]
```

---

## 5. Agent (Simple State Management)

Agent is an abstraction layer on top of GenServer, extremely useful for storing simple state or writing mock data during quick testing without spinning up a full, complex GenServer.

```elixir
# Start Agent, storing an initial state as a Map
{:ok, agent_pid} = Agent.start_link(fn -> %{count: 0} end)

# Read state (Get)
count = Agent.get(agent_pid, fn state -> state.count end)

# Update state (Update)
Agent.update(agent_pid, fn state -> Map.put(state, :count, state.count + 1) end)

# Update and return the result simultaneously (Get & Update)
new_count = Agent.get_and_update(agent_pid, fn state ->
  new_val = state.count + 1
  # Return format: {return_value, new_state}
  {new_val, %{state | count: new_val}}
end)

# Stop Agent
Agent.stop(agent_pid)
```

---

## 6. Timer & ETS Operations (In-Memory Caching)

### 6.1. Scheduled Messages (Timer)
```elixir
# Send the message {:timeout, :job_expired} to itself (self()) after 3000ms
timer_ref = Process.send_after(self(), {:timeout, :job_expired}, 3000)

# Cancel timer (returns the remaining ms or false if it has already run)
Process.cancel_timer(timer_ref)
```

### 6.2. Initializing & Manipulating ETS Tables
```elixir
# Initialize table (runs only once, typically in init/1 of the managing GenServer)
# Type options: :set (unique key), :ordered_set, :bag (keys can duplicate), :duplicate_bag
# Permissions: :protected (owner writes, everyone reads), :public (everyone reads/writes), :private (only owner reads/writes)
# :named_table allows calling by the Atom table name instead of reference ID.
:ets.new(:my_cache, [:set, :protected, :named_table])

# Write data: Format is a tuple, the first element is always the Key by default
:ets.insert(:my_cache, {key, val, extra_data})

# Read data: Always returns a list of tuples matching the key (even for :set)
case :ets.lookup(:my_cache, key) do
  [{^key, val, _extra}] -> {:ok, val}
  [] -> {:error, :not_found}
end

# Delete record
:ets.delete(:my_cache, key)

# Atomic Counter increment - Extremely important for Rate Limiting!
# Increment the element at index 2 (1-based index) of the tuple {key, count} by 1 unit
new_count = :ets.update_counter(:my_cache, key, {2, 1})
```

---

## 7. Ecto Syntax & Transaction Management (`Ecto.Multi`)

### 7.1. Basic Ecto Query (Joins & Preloads)
```elixir
import Ecto.Query

# More complex filtering, joining, and preloading query
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
    |> unique_constraint(:email) # Check duplicate at DB level upon insertion
  end
end
```

### 7.3. Ecto.Multi Pipeline (Safely execute a chain of DB actions)
```elixir
alias Ecto.Multi

multi =
  Multi.new()
  # 1. Add an insert/update action for an existing struct
  |> Multi.insert(:create_profile, %Profile{bio: "Hello"})
  
  # 2. Add a custom action (receives repo and the results of previous steps via changes)
  |> Multi.run(:debit_account, fn repo, _changes ->
    case repo.get(Account, from_id) do
      nil -> {:error, :account_not_found}
      account ->
        # Business logic...
        {:ok, updated_account}
    end
  end)
  
  # 3. Use the result of the previous :debit_account step
  |> Multi.run(:log_transaction, fn repo, %{debit_account: account} ->
    # log logic...
    {:ok, log_record}
  end)

# Real execution
case Repo.transaction(multi) do
  {:ok, %{debit_account: acc, log_transaction: log}} ->
    # Success, returns a map containing the results of each step
    {:ok, acc}
    
  {:error, failed_step, failed_value, changes_so_far} ->
    # Failure, all previous steps have been automatically rolled back
    # failed_step will be the atom name (like :debit_account) where the error occurred
    {:error, failed_step, failed_value}
end
```

---

## 8. Process Link, Monitor & Trap Exit (OTP Error Handling)

### 8.1. Monitor another Process (One-way)
```elixir
# Create a one-way monitor. If the pid dies, the current process will receive a {:DOWN, ...} message
ref = Process.monitor(pid)

# Receive DOWN message in handle_info/2
@impl true
def handle_info({:DOWN, ref, :process, pid, reason}, state) do
  IO.puts("Process #{inspect(pid)} died because of #{inspect(reason)}")
  {:noreply, state}
end
```

### 8.2. Trap Exit (Transform exit signals into regular messages)
```elixir
# Run in init/1 to prevent the current process from dying when a linked process crashes
Process.flag(:trap_exit, true)

# Receive message when linked process dies
@impl true
def handle_info({:EXIT, dead_pid, reason}, state) do
  IO.puts("Linked process #{inspect(dead_pid)} exited with #{inspect(reason)}")
  {:noreply, state}
end
```

---

## 9. File Operations & Lazy Operations (Streams)

Very useful when reading large log files or processing large streams of data.

### 9.1. Basic File Read/Write
```elixir
# Read entire file into RAM
{:ok, content} = File.read("path/to/file.txt")

# Overwrite file
:ok = File.write("path/to/file.txt", "content details")

# Append to the end of the file
:ok = File.write("path/to/file.txt", "new log line\n", [:append])
```

### 9.2. Stream (Lazily process file line-by-line, without loading everything into RAM)
```elixir
# Read file, filter lines containing error, and save to a new file lazily
File.stream!("huge_development.log")
|> Stream.map(&String.trim/1)
|> Stream.filter(fn line -> String.contains?(line, "[ERROR]") end)
|> Stream.take(100) # Only take the first 100 error lines
|> Stream.into(File.stream!("errors_only.log"))
|> Stream.run() # Start actual execution
```

---

## 10. Map, List Manipulation & Masterful Pattern Matching

### 10.1. Updating Nested Maps
```elixir
# Use put_in to modify value along a key path
new_map = put_in(map, [:user, :profile, :age], 30)

# Use update_in to compute new value based on the old value
new_map = update_in(map, [:user, :profile, :age], fn age -> age + 1 end)
```

### 10.2. Grouping/Aggregating using `Enum.reduce/3`
```elixir
# Calculate sum of values in a list
total = Enum.reduce([1, 2, 3], 0, fn num, acc -> num + acc end)

# Categorize list into a grouped Map
grouped = Enum.reduce(users, %{}, fn user, acc ->
  Map.update(acc, user.role, [user], fn list -> [user | list] end)
end)
```

### 10.3. Map.update/4 and Map.get_and_update/3
```elixir
# Map.update/4: Update key, or set default initial value if key does not exist
updated_map = Map.update(map, :counter, 1, fn current_val -> current_val + 1 end)

# Map.get_and_update/3: Retrieve the old value and update with the new value at the same time
{old_val, new_map} = Map.get_and_update(map, :status, fn
  nil -> {nil, "active"}
  current -> {current, "updated_" <> current}
end)
```

### 10.4. Powerful Pattern Matching & Guard Clauses
```elixir
# Match complex Map structure directly in function parameters with Guards
def process_user(%{status: "active", profile: %{age: age}} = user) when age >= 18 and is_integer(age) do
  {:ok, :adult, user}
end
def process_user(_user), do: {:error, :unauthorized}
```

---

## 11. Error Handling (Exceptions & try/catch)

```elixir
# 1. Custom Exception
defmodule MyApp.CustomError do
  defexception message: "something went wrong", details: nil
end

# Raise error
# raise MyApp.CustomError, message: "DB timeout"

# 2. Exception handling
try do
  # Code that might raise an error here
  1 / 0
rescue
  e in ArithmeticError -> 
    IO.puts("Handled division by zero: #{e.message}")
  e in MyApp.CustomError ->
    IO.puts("Handled custom error: #{e.message}")
after
  # Always runs (like finally in JS/Java)
  IO.puts("This always runs")
end
```

---

## 12. Erlang Interop (Calling useful Erlang libraries)

Erlang comes with extremely powerful core libraries that you can call directly from Elixir.

### 12.1. Hash & Crypto (Using `:crypto`)
```elixir
# Generate MD5 / SHA256 hashes
sha256_binary = :crypto.hash(:sha256, "my_secret_string")
hex_string = Base.encode16(sha256_binary, case: :lower) # Convert to hex string format

# Calculate HMAC (very commonly used for signing tokens/signatures)
hmac_binary = :crypto.mac(:hmac, :sha256, "my_secret_key", "data_to_sign")
```

### 12.2. Optimized FIFO Queue (Using `:queue`)
When you need a practical Queue that runs extremely fast, much faster than appending to the end of an Elixir List.
```elixir
# Initialize empty Queue
q = :queue.new()

# Add to the tail (In)
q = :queue.in("task1", q)
q = :queue.in("task2", q)

# Retrieve from the head (Out)
case :queue.out(q) do
  {{:value, item}, remaining_q} -> 
    # item = "task1"
    {:ok, item, remaining_q}
  {:empty, _q} -> 
    {:error, :empty}
end
```

---

## 13. Telemetry (Emitting metrics for system monitoring)

For questions regarding Observability / Monitoring.

```elixir
# 1. Emit a telemetry event with measurements and metadata
:telemetry.execute(
  [:my_app, :jobs, :complete], # Event name (list of atoms)
  %{duration: 120},            # Measurements (usually execution time, count...)
  %{job_id: "123", status: :ok} # Metadata
)

# 2. Listen to the event (typically configured in the Application start module)
:ok = :telemetry.attach(
  "my-listener-id",            # Unique Handler ID
  [:my_app, :jobs, :complete], # Event to listen to
  &MyApp.TelemetryHandler.handle_event/4, # Callback function
  nil                          # config / additional state passed
)
```

---

## 14. Unit Testing Skeleton (`ExUnit`)

Used to run tests to verify your code right during a live coding session.

```elixir
ExUnit.start()

defmodule MyPracticeTest do
  use ExUnit.Case, async: true

  # Setup structure to mock/initialize state before running tests
  setup do
    # Start Sandbox if testing with Ecto Database
    # :ok = Ecto.Adapters.SQL.Sandbox.checkout(MyApp.Repo)
    
    {:ok, db_conn: :connected, temp_user_id: "user_999"}
  end

  test "description of a successful test case", %{db_conn: conn, temp_user_id: user_id} do
    assert conn == :connected
    assert user_id == "user_999"
    refute 1 == 2 # refute is the opposite of assert (expects a false result)
  end

  test "description of an expected error test case" do
    assert_raise ArithmeticError, fn -> 1 / 0 end
  end
end
```
