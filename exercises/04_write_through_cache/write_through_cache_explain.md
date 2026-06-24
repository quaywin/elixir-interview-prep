# 💡 Exercise Explanation: Write-Through Cache (`ETS` & `GenServer`)

## 1. Real-world Requirements & Design
In extremely high-throughput systems (such as API Gateways, User Session validators, or Product Catalogs), the number of read requests is typically tens to hundreds of times higher than write requests.
If every read request had to send a message through a single GenServer, that GenServer would become a bottleneck due to sequential mailbox processing.

**Solution:**
*   Use **ETS (Erlang Term Storage)** for in-memory caching. The ETS table is configured as `:protected`.
*   **Read Operation:** Executed directly in the context of the caller process (e.g., Phoenix Controller) by querying the ETS table. It does not go through the GenServer's mailbox. Multiple processes can read from this ETS table with 100% concurrency.
*   **Write Operation:** Must send a message through the `CacheService` GenServer. This GenServer performs a synchronous write to the Database first to guarantee durability (Persistence), and then updates the ETS cache table with the new data.

---

## 2. Implementation Code Explanation

### 2.1. Reading Directly from Caller Context (Bypassing GenServer)
```elixir
def read(key) do
  # This function is executed by the caller process itself (e.g., a Task or Web Connection process)
  case :ets.lookup(@table_name, key) do
    [{^key, value}] -> {:ok, value}
    [] -> {:error, :not_found}
  end
end
```
*   Thanks to this mechanism, read throughput can approach the physical limits of RAM (up to several million reads/second). The `CacheService` GenServer remains completely free to focus on other tasks.

### 2.2. Synchronous Write Transaction via GenServer Owner
```elixir
# Initialize the ETS table in the GenServer's init/1
def init(_opts) do
  # :set -> Unique Key-Value structure
  # :protected -> Only the Owner process (this GenServer) can write; other processes can only read
  # :named_table -> Allows using the atom name :CacheTable instead of managing via tid (Table ID)
  :ets.new(@table_name, [:set, :protected, :named_table])
  {:ok, %{}}
end

# Handle write transaction
def handle_call({:write, key, value}, _from, state) do
  # 1. Write data to DB first
  case MockDB.write(key, value) do
    :ok ->
      # 2. DB write success -> overwrite the ETS cache
      :ets.insert(@table_name, {key, value})
      {:reply, :ok, state}
    
    _error ->
      {:reply, {:error, :db_write_failed}, state}
  end
end
```

---

## 3. Critical Technical Aspects

### 3.1. Why must the ETS table be configured as `:protected`?
*   `:private`: Only the Owner process can read and write. Other processes calling `:ets.lookup` will crash with a `:badarg` error. Cannot be used as a shared cache.
*   `:public`: Any process can read and write. This easily leads to data **Race Conditions** (e.g., Process A reads the DB and overwrites the ETS cache with stale data at the exact moment Process B is writing new data).
*   `:protected`: Guarantees the highest consistency. Only the `CacheService` GenServer is authorized to modify the ETS table's data after confirming a successful write to the Database. All other processes only have read access to the static data, eliminating write conflicts entirely.

### 3.2. Cache Invalidation
In a Write-Through design:
*   Data is always written to the DB and the Cache concurrently, so the Cache is never out of sync with the DB (Strong consistency).
*   However, if the Database is modified directly from the outside (for example, an administrator manually edits the DB), the Cache will become out-of-date (stale data). 
*   *Workaround:* A database change listener mechanism (CDC - Change Data Capture) is needed, or a Time To Live (TTL) should be established for each record in ETS to automatically evict it after a period.
