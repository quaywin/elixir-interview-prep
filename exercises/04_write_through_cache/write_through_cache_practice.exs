# ==============================================================================
# PRACTICE EXERCISE DAY 1 (ADVANCED 3): WRITE-THROUGH CACHE WITH ETS & GENSERVER
# ==============================================================================
# Problem: Design a Write-Through Cache system.
# Clients can read data concurrently and extremely fast from the ETS table without bottlenecks.
# But write operations must call through a GenServer to write to the Database (DB)
# synchronously first, then update the ETS table.
#
# Requirements:
# 1. The system consists of:
#    - An ETS table named `CacheTable` initialized as `:set` and `:protected`.
#      The GenServer `CacheService` acts as the Owner of this ETS table.
#    - A mock database simulated by an Agent (`MockDB`).
# 2. Define the client API in `CacheService`:
#    - `read(key)`: READ DIRECTLY from the ETS table `CacheTable` using `:ets.lookup/2`
#      within the context of the caller process. Absolutely DO NOT use `GenServer.call` to avoid bottlenecks.
#      If cache hit -> return `{:ok, value}`.
#      If cache miss -> return `{:error, :not_found}` (no need to auto-load from the DB here).
#    - `write(key, value)`: WRITE SYNCHRONOUSLY by sending `GenServer.call` to `CacheService`.
# 3. When receiving a `write(key, value)` request, `CacheService` GenServer will:
#    - Call the mock DB write (`MockDB.write(key, value)`).
#    - If DB write succeeds -> update the key-value in the ETS table `CacheTable`.
#    - Return `:ok` to the caller.
#
# Run this file with the command: elixir write_through_cache_practice.exs
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
    # Simulate database write latency (slow I/O)
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
  Reads data extremely fast from the cache.
  REQUIREMENT: Read operations must run fully synchronously on the caller process (e.g., HTTP Controller)
  by directly calling the ETS table. Do not send messages to the GenServer.
  """
  def read(key) do
    # Call :ets.lookup(@table_name, key)
    # Data format in ETS is {key, value}
    # Returns:
    # - `{:ok, value}` if found.
    # - `{:error, :not_found}` if not found.
    case :ets.lookup(@table_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Writes data synchronously.
  REQUIREMENT: Write operations must go through the GenServer to write to the DB first, then update the cache.
  """
  def write(key, value) do
    GenServer.call(__MODULE__, {:write, key, value})
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(_opts) do
    # Initialize ETS table
    # REQUIREMENT: :set, :protected, :named_table (to use atom as table name)
    # :protected means only the Owner process (this GenServer) has write permissions,
    # but any other process can read.
    :ets.new(@table_name, [:set, :protected, :named_table])

    {:ok, %{}}
  end

  @impl true
  def handle_call({:write, key, value}, _from, state) do
    # 1. Write to mock Database
    case MockDB.write(key, value) do
      :ok ->
        # 2. If DB write succeeds, update the ETS cache table
        # Format stored is a tuple {key, value}
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
    # Start mock Database with an empty map
    start_supervised!({MockDB, %{}})
    # Start Cache Service
    start_supervised!(CacheService)
    :ok
  end

  test "successfully reads/writes data synchronously and updates cache" do
    # Newly initialized, cache must be empty
    assert {:error, :not_found} = CacheService.read("username")

    # Write data through Cache Service
    assert :ok = CacheService.write("username", "alice")

    # Read directly from Cache (fast read from ETS)
    assert {:ok, "alice"} = CacheService.read("username")

    # Data must also be stored in the actual Database
    assert MockDB.read("username") == "alice"
  end

  test "different processes can read concurrently directly from ETS" do
    # Write data
    assert :ok = CacheService.write("session_token", "jwt_123456")

    # Spawn an independent child process and read the cache from it
    task =
      Task.async(fn ->
        CacheService.read("session_token")
      end)

    # Ensure successful read from child process (thanks to ETS :protected configuration)
    assert {:ok, "jwt_123456"} = Task.await(task)
  end

  test "cache miss does not automatically fetch from DB" do
    # Write directly to DB, bypassing Cache Service
    MockDB.write("bypass_key", "db_value")

    # Reading from cache service must return a cache miss (since it was not written through the service)
    assert {:error, :not_found} = CacheService.read("bypass_key")
  end
end
