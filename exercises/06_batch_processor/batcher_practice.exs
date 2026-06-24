# ==============================================================================
# ADVANCED PRACTICAL EXERCISE: BATCH PROCESSOR (CONCURRENCY & BATCHING)
# ==============================================================================
# Objective: Build a GenServer named `BatchProcessor` to batch data items
# (e.g., log records or database writes) and process them in batches.
#
# Requirements:
# 1. The GenServer accepts configuration parameters upon startup:
#    - `batch_size`: The maximum number of items in a batch (e.g., 5 items).
#    - `timeout`: The maximum waiting time (ms) to collect a batch before automatically flushing (e.g., 1000ms).
# 2. Define the client API:
#    - `add_item(item)`: Add an item asynchronously to the batch (cast or call).
#    - `flush()`: Proactively request a flush of current items at any time.
# 3. When `batch_size` items are collected OR the `timeout` expires without a full batch,
#    the GenServer must send the entire batch to the handler function `process_batch(items)`
#    and clear the queue in the state.
# 4. Use `:erlang.send_after/3` to manage the timeout flush. Be careful to cancel the old timer
#    if the batch is flushed early to prevent double-flushing.
#
# Run this file with the command: elixir batcher_practice.exs
# ==============================================================================

defmodule BatchProcessor do
  use GenServer

  # --- CLIENT API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds an item to the processing queue.
  """
  def add_item(item) do
    GenServer.call(__MODULE__, {:add_item, item})
  end

  @doc """
  Proactively flushes all current items in the queue for immediate processing.
  """
  def flush do
    GenServer.call(__MODULE__, :flush)
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(opts) do
    batch_size = Keyword.get(opts, :batch_size, 5)
    timeout = Keyword.get(opts, :timeout, 1000)

    callback =
      Keyword.get(opts, :callback, fn items -> IO.inspect(items, label: "Processed batch") end)

    state = %{
      batch_size: batch_size,
      timeout: timeout,
      callback: callback,
      queue: [],
      timer: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_item, item}, _from, state) do
    new_queue = state.queue ++ [item]

    if length(new_queue) >= state.batch_size do
      cancel_timer(state.timer)
      state.callback.(new_queue)
      {:reply, :ok, %{state | queue: [], timer: nil}}
    else
      timer =
        if is_nil(state.timer) do
          :erlang.send_after(state.timeout, self(), :timeout_flush)
        else
          state.timer
        end

      {:reply, :ok, %{state | queue: new_queue, timer: timer}}
    end
  end

  @impl true
  def handle_call(:flush, _from, state) do
    cancel_timer(state.timer)

    if length(state.queue) > 0 do
      state.callback.(state.queue)
    end

    {:reply, :ok, %{state | queue: [], timer: nil}}
  end

  @impl true
  def handle_info(:timeout_flush, state) do
    if length(state.queue) > 0 do
      state.callback.(state.queue)
    end

    {:noreply, %{state | queue: [], timer: nil}}
  end

  # Helper to cancel a timer safely
  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: :erlang.cancel_timer(timer)
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule BatchProcessorTest do
  use ExUnit.Case
  @moduletag :capture_log

  setup do
    # Simulate a test agent to check if the batches are sent correctly
    {:ok, agent} = Agent.start_link(fn -> [] end)
    callback = fn items -> Agent.update(agent, fn state -> state ++ [items] end) end

    # Start BatchProcessor with batch_size = 3 and timeout = 100ms
    start_supervised!({BatchProcessor, batch_size: 3, timeout: 100, callback: callback})

    {:ok, agent: agent}
  end

  test "automatically processes and resets the queue when batch_size is reached", %{agent: agent} do
    assert :ok = BatchProcessor.add_item("item_1")
    assert :ok = BatchProcessor.add_item("item_2")
    # Not enough items (under 3), callback not called yet
    assert Agent.get(agent, & &1) == []

    assert :ok = BatchProcessor.add_item("item_3")
    # Exactly 3 items, callback must be called
    assert Agent.get(agent, & &1) == [["item_1", "item_2", "item_3"]]
  end

  test "automatically flushes after timeout even if batch_size is not reached", %{agent: agent} do
    assert :ok = BatchProcessor.add_item("item_1")
    assert :ok = BatchProcessor.add_item("item_2")
    # Wait 150ms (> timeout 100ms)
    Process.sleep(150)
    # The system must automatically flush
    assert Agent.get(agent, & &1) == [["item_1", "item_2"]]
  end

  test "proactively flushes using the client API", %{agent: agent} do
    assert :ok = BatchProcessor.add_item("item_1")
    assert :ok = BatchProcessor.flush()
    assert Agent.get(agent, & &1) == [["item_1"]]
  end
end
