# 📔 Core OTP & Database Prep: BEAM VM Architecture, OTP Internals & Database Mechanics (Ecto)

This document does not provide short answers for rote memorization. It explains the **underlying mechanics (how it works under the hood)** and **design rationale (why it was designed this way)** of the BEAM VM, OTP, and Ecto to help you build the systems thinking of a Senior Engineer.

---

## 1. How the BEAM VM Works (Erlang Run-Time System - ERTS)

### 1.1. Preemptive Scheduling Mechanics
In most operating systems and programming languages (such as Go or Node.js), scheduling is **Cooperative**. This means a thread (or goroutine) must actively yield control when encountering I/O operations or calling specific yield functions to let other threads run. If you write an infinite loop performing mathematical calculations, it will completely block that thread.

The BEAM VM solves this problem using **Preemptive Scheduling** based on the concept of **Reductions**:

```
+-------------------------------------------------------------------+
|                           Scheduler Thread                        |
+-------------------------------------------------------------------+
       |
       v
+-----------------+
|   Run Queue     | ---> [Process A] -> [Process B] -> [Process C]
+-----------------+
       |
       | 1. Fetch Process A to run
       v
+-------------------------------------------------------------------+
| Execute: Process A                                                |
| - Each function call, operation, message sent = 1 Reduction       |
| - Maximum budget: 2000 Reductions                                 |
+-------------------------------------------------------------------+
       |
       | 2. Once 2000 Reductions are consumed (or blocked by I/O)
       v
+-------------------------------------------------------------------+
| Context Switch:                                                   |
| - Save Program Counter (PC) and registers of Process A            |
| - Push Process A to the end of the Run Queue                      |
| - Fetch Process B to continue running                             |
+-------------------------------------------------------------------+
```

*   **What is a Reduction?** It is a unit of work measurement in the BEAM VM. Each function call, BIF (Built-in Function) execution, or pattern matching comparison consumes reductions.
*   **Ultra-lightweight Context Switching in BEAM:** Unlike operating system context switches (which require virtual address space switching, Page Table flushes, and transition from User Mode to Kernel Mode), a BEAM Process is just a data structure in user-space. A context switch simply involves saving a few pointer registers (Stack Pointer, Program Counter) into that process's PCB (Process Control Block) memory area. This cost takes less than a few nanoseconds.
*   **Work Stealing:** Each physical CPU Core is mapped to 1 Scheduler Thread managing its own Run Queue. If the Run Queue of Scheduler 1 is empty, it will lock and "steal" a few processes from the end of Scheduler 2's Run Queue to ensure all cores are utilized evenly, optimizing multi-core hardware.

---

### 1.2. Memory Architecture & Garbage Collection (GC)
To understand why the BEAM VM never experiences a "Stop-the-world" pause (where the entire application stops to perform garbage collection, as in Java), we need to look at the memory layout of an individual Process:

```
+-----------------------------------------------------------------------+
| BEAM Process Memory Layout                                            |
|                                                                       |
|  +-----------------------------------------------------------------+  |
|  | Process Control Block (PCB)                                     |  |
|  | - Pid, Status, Mailbox pointers, Links/Monitors list            |  |
|  +-----------------------------------------------------------------+  |
|  | Stack (Grows downwards)                                         |  |
|  | - Contains local variables, function arguments, return addresses|  |
|  |            |                                                    |  |
|  |            v                                                    |  |
|  |                                                                 |  |
|  |            ^                                                    |  |
|  |            |                                                    |  |
|  | Heap (Grows upwards)                                            |  |
|  | - Contains Tuples, Lists, Maps, Heap Binaries (< 64 bytes)      |  |
|  +-----------------------------------------------------------------+  |
|                                                                       |
+-----------------------------------------------------------------------+
```

*   **Why use a Private Heap?**
    *   **No lock contention:** Since each process owns its own memory area, it doesn't need to acquire a lock (mutex lock) to allocate new memory. Allocation is simply a matter of incrementing the Heap Pointer (bumping allocator), which is extremely fast.
    *   **Independent GC:** Garbage collection runs only on the Heap of the specific process running low on memory. The other 99% of processes continue executing normally.
    *   **Trade-off:** When sending a message between Process A and Process B, the data must be **copied (deep copied)** from the Heap of A to the Heap of B. This incurs CPU overhead if the message size is large.
*   **Generational GC Mechanism:**
    *   **Young Heap (New generation):** Most variables in functional programming have very short lifespans. When cleaning the Young Heap, BEAM uses a *Copying Collector* algorithm. It scans active variables from the Stack, copies them to a brand-new contiguous memory space (To-space) to prevent fragmentation, and then frees the entire old memory space (From-space).
    *   **Old Heap (Old generation):** If a variable survives multiple Minor GCs, it is "promoted" to the Old Heap. When the Old Heap becomes full, a Major GC runs using a *Sweep* algorithm (which is more expensive).
*   **Binary Storage Mechanism (Off-heap Binaries):**
    *   If you store a 5MB HTML string on the Heap of Process A, sending it to Process B would require copying 5MB and consuming another 5MB of memory.
    *   **BEAM's Solution:** Any binary **> 64 bytes** (called a *Refc Binary*) is stored in a **Global Shared Heap** outside of individual processes.
    *   The Heap of Process A and B then only contains a **ProcBin** (24 bytes) containing a pointer referencing that Global memory block and its byte size.
    *   **Memory Leaks with Sub-binaries:** When you parse a massive 20MB JSON string and extract a small token like `\"user_123\"` (18 bytes), keeping this token in the GenServer's state retains a reference to the entire original 20MB binary (since it is a sub-binary slice). The system will not be able to free this 20MB block from the Global Heap.
    *   *Solution:* Call `:binary.copy(\"user_123\")`. This function copies the 18-byte string directly into the process's internal Heap (as a Heap Binary because it is < 64 bytes) and breaks the connection to the original 20MB block, allowing GC to clean up the 20MB block.

---

## 2. The Inner Workings of OTP (Open Telecom Platform)

### 2.1. What is a GenServer, Really?
Don't think of a GenServer as a class or some magic component. Under the hood of the BEAM, a GenServer is simply an **Erlang Process running an infinite tail-recursive loop**:

```elixir
defmodule MyGenServer do
  # Function to start the process
  def start_link(init_arg) do
    spawn_link(fn -> loop(init_arg) end)
  end

  # Message receiving loop
  defp loop(state) do
    receive do
      {:call, from, :get_state} ->
        send(from, {:reply, state})
        loop(state) # Continue recursing to keep the process alive

      {:cast, {:update, new_val}} ->
        new_state = process_update(state, new_val)
        loop(new_state) # Update with the new state for the next iteration
    end
  end
end
```

*   **Mailbox:** Each process has a message queue structured as a singly linked list. When you send a message to a process, the message is copied to the end of this list.
*   **Selective Receive:** When a `receive` statement runs, the BEAM traverses the Mailbox from the beginning to find a message matching the pattern. If a message does not match, it is put into a temporary queue (the save queue). If your Mailbox accumulates millions of unmatched messages, the BEAM will have to traverse millions of elements every time a new message arrives, causing severe performance degradation.
*   **Why is `init` blocking?** When a Supervisor calls `start_link`, it uses a synchronous mechanism (`GenServer.start_link`). The Supervisor process blocks completely, waiting for a response from the child process's `init/1` function. If `init/1` calls an external API that takes 10 seconds, the entire boot sequence of the application hangs, causing the Supervisor to crash because it exceeds its timeout threshold (typically 5000ms).
*   **The `handle_continue` Mechanism:**
    ```
    Supervisor calls start_link() -> Runs init() 
                                      | (Returns {:ok, state, {:continue, :step}})
                                      v
    Supervisor receives ok, releases block (App continues booting)
                                      |
                                      v
    GenServer immediately sends message {:continue, :step} to itself
    (This message is inserted at the head of the Mailbox, running before any external requests)
                                      |
                                      v
                               Runs handle_continue()
    ```

---

### 2.2. Avoiding Bottlenecks
Since a GenServer processes messages in its Mailbox **sequentially (FIFO - First In First Out)** on a single process, if you have 10,000 requests/second querying the same GenServer to read configuration info, those requests will queue up in the Mailbox, driving up latency.

#### Solution 1: ETS (Erlang Term Storage) - Concurrent Read/Write
ETS is an in-memory storage engine written in C directly within the Erlang runtime.
*   It allows any process to directly read data without passing a message through the GenServer (avoiding data serialization/deserialization overhead in the mailbox).
*   **Standard Design Pattern:** A GenServer acts as the "writer" (handles writes and updates the ETS table). Web controllers act as "readers" (reading directly from the ETS table using `:ets.lookup/2`). This boosts throughput to hundreds of thousands of requests/second because read operations run fully in parallel.

#### Solution 2: PartitionSupervisor
If you must perform stateful write/processing tasks:
*   A `PartitionSupervisor` will spawn a pool of $N$ child GenServers.
*   Upon receiving a request, the system hashes a key (e.g., `user_id`) to determine which worker process handles that request. This load-balances requests across different processes, resolving the bottleneck.

---

## 3. The Nature of Ecto Queries & PostgreSQL

### 3.1. How Does Ecto.Multi Work?
Many engineers mistakenly believe that `Ecto.Multi` immediately opens a transaction and locks the database. In reality:
*   `Ecto.Multi` is a **pure data structure builder**. When you call `Ecto.Multi.new() |> Ecto.Multi.run(...)`, you are merely building a declarative list of commands/functions. No database connections are opened during this step.
*   Only when you call `Repo.transaction(multi)` does Ecto actually:
    1. Check out a database connection from the pool.
    2. Issue a `BEGIN` statement to open a transaction in Postgres.
    3. Run each step in the Multi sequentially.
    4. If all steps succeed, issue `COMMIT`.
    5. If any step fails (returning `{:error, reason}`), Ecto immediately issues a `ROLLBACK` to restore the database to its original state and returns the connection to the pool.

### 3.2. N+1 Queries: The Underlying Mechanics
Suppose you have 100 Users, and each User has many Orders. You want to print each User's name along with their list of Orders.

*   **Incorrect approach (N+1):**
    ```elixir
    users = Repo.all(User) # 1 query to get 100 users
    Enum.each(users, fn user ->
      orders = Repo.all(assoc(user, :orders)) # 100 queries to get orders for each user
      IO.inspect({user.name, orders})
    end)
    ```
    *Mechanics:* 101 network calls to PostgreSQL. Total latency = 101 * Round-trip time (RTT). If RTT = 5ms, you spend at least 500ms just waiting on the network.

*   **Fixing with Preload (2 Queries):**
    ```elixir
    users = Repo.all(User) |> Repo.preload(:orders)
    ```
    *Under the hood:* Ecto executes query 1: `SELECT * FROM users;`. Ecto collects all IDs of the retrieved users (e.g., `[1, 2, 3, ..., 100]`). Then it executes query 2: `SELECT * FROM orders WHERE user_id IN (1, 2, 3, ..., 100);`. Finally, Ecto automatically maps the retrieved Order records to the correct User structs in the application's RAM. This takes only 2 RTTs (10ms).

*   **Fixing with Join (1 Query):**
    ```elixir
    query = from u in User,
              join: o in assoc(u, :orders),
              preload: [orders: o]
    users = Repo.all(query)
    ```
    *Under the hood:* Only 1 query is sent to the DB using `INNER JOIN` or `LEFT OUTER JOIN`. Postgres associates the data in its disk/memory layer and returns a single flat result set. Ecto parses this result set to rebuild the nested structs. This approach is ideal when you need to filter Users based on Order conditions (e.g., find Users with an order exceeding 1 million VND).

---

## 🚀 Practical Exercises (exercises/)
*   **[01_ledger]**: Secure Ecto.Multi transactions. -> [Exercise](exercises/01_ledger/ledger_practice.exs) | [Explanation](exercises/01_ledger/ledger_explain.md)
*   **[02_session_manager]**: Dynamic Process Management (DynamicSupervisor + Registry). -> [Exercise](exercises/02_session_manager/session_manager_practice.exs) | [Explanation](exercises/02_session_manager/session_manager_explain.md)
*   **[03_job_queue]**: Concurrent Job Queue (Task.Supervisor + Monitor). -> [Exercise](exercises/03_job_queue/job_queue_practice.exs) | [Explanation](exercises/03_job_queue/job_queue_explain.md)
*   **[04_write_through_cache]**: Designing a Write-Through Cache with ETS tables. -> [Exercise](exercises/04_write_through_cache/write_through_cache_practice.exs) | [Explanation](exercises/04_write_through_cache/write_through_cache_explain.md)
*   **[07_algorithms]**: Data structures & algorithms solved using Elixir functional programming. -> [Exercise](exercises/07_algorithms/algorithm_practice.exs) | [Cheat Sheet](exercises/07_algorithms/algorithm_tricks.md)
