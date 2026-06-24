# 💡 Exercise Explanation: Batch Processor (`GenServer` & `Timer` & `Cancellation`)

## 1. Practical Requirements & Design
In logging systems (such as sending telemetry metrics, writing audit logs, or pushing data to ElasticSearch), writing each individual record to disk or invoking an external API for every request would create a massive IOPS load and high latency.
The optimal solution is **Batching**: collect up to 100 items or wait for a maximum of 1 second before writing them all at once.

**Design requirements:**
*   A GenServer `BatchProcessor` receives items and temporarily stores them in the list `state.queue`.
*   If the queue size reaches `batch_size` -> Call the write callback immediately.
*   If the queue hasn't reached `batch_size` but the `timeout` expires -> Automatically trigger a flush of the current data.
*   **Crucial Point (Senior Level):** If the data is flushed early because `batch_size` is reached before the timeout, the old timer must be cancelled. Otherwise, when that timer expires, it will send a second flush message, leading to logical errors or processing empty batches.

---

## 2. Implementation Code Explanation

```elixir
defmodule BatchProcessor do
  use GenServer

  # ... Client API ...

  @impl true
  def handle_call({:add_item, item}, _from, state) do
    new_queue = state.queue ++ [item]

    if length(new_queue) >= state.batch_size do
      # BATCH SIZE REACHED: Flush immediately
      # 1. Cancel the old timer (if any)
      cancel_timer(state.timer)
      
      # 2. Process data
      state.callback.(new_queue)
      
      # 3. Reset the queue and timer
      {:reply, :ok, %{state | queue: [], timer: nil}}
    else
      # BATCH SIZE NOT REACHED YET: Wait for more
      # 4. If no timer is running, initialize a new one
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
    # EXPLICIT FLUSH VIA API
    cancel_timer(state.timer)
    if length(state.queue) > 0 do
      state.callback.(state.queue)
    end
    {:reply, :ok, %{state | queue: [], timer: nil}}
  end

  @impl true
  def handle_info(:timeout_flush, state) do
    # FLUSH DUE TO TIMEOUT
    if length(state.queue) > 0 do
      state.callback.(state.queue)
    end
    {:noreply, %{state | queue: [], timer: nil}}
  end

  # Helper to cancel a timer safely
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: :erlang.cancel_timer(timer)
end
```

---

## 3. Key Points from a Technical Perspective

### 3.1. Safe Timer Cancellation (`:erlang.cancel_timer/1`)
*   When `:erlang.send_after/3` is called, it returns a reference.
*   If we do not call `:erlang.cancel_timer(timer)`, the `:timeout_flush` message will inevitably be pushed to the GenServer's mailbox when the timer expires.
*   *Note on Race Conditions:* Sometimes, you call `cancel_timer(timer)` at the exact microsecond the `:timeout_flush` message has already arrived in the GenServer's mailbox. For absolute safety, in the `handle_info(:timeout_flush)` handler, we check the condition `if length(state.queue) > 0`. If the queue was already cleared by an early flush, we simply ignore it and do nothing, avoiding sending an empty batch to the callback.

### 3.2. List Concatenation Performance (`state.queue ++ [item]`)
*   In functional programming, lists are Singly Linked Lists. The `list ++ [item]` operation (appending to the end) has an $O(N)$ time complexity because it has to traverse the entire list to construct the new one.
*   If the `batch_size` is large (e.g., 10,000 items), repeatedly calling `list ++ [item]` will severely degrade CPU performance due to continuous memory reallocation.
*   *Optimal Solution:* Prepend items to the list using the cons operator: `new_queue = [item | state.queue]`, which runs in $O(1)$ time. When flushing, simply reverse the list once using `:lists.reverse(new_queue)` (or `Enum.reverse/1`) before passing it to the callback.
