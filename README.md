# Elixir Concurrency & OTP Playground

A collection of advanced Elixir exercises and reference implementations focusing on OTP behaviors, concurrent state management, database transactions, and data processing pipelines.

---

## 🚀 Getting Started

All exercises are designed as standalone Elixir scripts (`.exs`) with built-in `ExUnit` tests. You can run them directly using the Elixir CLI without creating a Mix project.

```bash
# Run ledger transaction practice (Ecto.Multi)
elixir exercises/01_ledger/ledger_practice.exs

# Run session manager practice (DynamicSupervisor & Registry)
elixir exercises/02_session_manager/session_manager_practice.exs

# Run job queue coordinator (Task.Supervisor & monitor)
elixir exercises/03_job_queue/job_queue_practice.exs

# Run write-through cache (ETS & GenServer)
elixir exercises/04_write_through_cache/write_through_cache_practice.exs

# Run rate limiter (GenServer & reset timer)
elixir exercises/05_rate_limiter/rate_limiter_practice.exs

# Run batch processor (Batcher & dynamic flushing)
elixir exercises/06_batch_processor/batcher_practice.exs

# Run functional algorithms (Word reversal, anagram grouping, stacks)
elixir exercises/07_algorithms/algorithm_practice.exs
```

---

## 📂 Project Structure

*   **`exercises/01_ledger`**: Implements safe financial transfers using transactional safety with mock database adapters.
*   **`exercises/02_session_manager`**: Demonstrates dynamic process supervision and routing using `DynamicSupervisor` and `Registry`.
*   **`exercises/03_job_queue`**: Orchestrates asynchronous tasks with concurrency limits using a custom task coordinator.
*   **`exercises/04_write_through_cache`**: A hybrid cache showing concurrent reads from ETS tables alongside synchronous writes to databases.
*   **`exercises/05_rate_limiter`**: A rate-limiting implementation tracking request frequencies with dynamic reset behaviors.
*   **`exercises/06_batch_processor`**: Buffers incoming data streams and flushes them in batches based on size or time thresholds.
*   **`exercises/07_algorithms`**: Core algorithms (brackets, anagrams, string parsing) solved using pure functional patterns.

---

## 📝 Syntax Reference

A quick reference guide for common Elixir/OTP boilerplate (including GenServer, Registry, DynamicSupervisor, ETS, Ecto.Multi, and Task.Supervisor) is available in [exercises/syntax_cheat_sheet.md](exercises/syntax_cheat_sheet.md).
