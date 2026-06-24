# ==============================================================================
# PRACTICE EXERCISE DAY 1 (ADVANCED 2): CONCURRENT JOB QUEUE
# ==============================================================================
# Problem: Build a GenServer named `JobQueue` to manage the execution of
# asynchronous tasks (jobs) with a limit on the maximum number of concurrent runs
# (max concurrency).
#
# Requirements:
# 1. GenServer accepts configuration options upon startup:
#    - `max_concurrency`: Maximum number of jobs allowed to run concurrently (e.g., 2 jobs).
# 2. Define the client API:
#    - `enqueue(job_fun)`: Add a job (as an anonymous function) to the queue.
# 3. When there is an available slot (number of running jobs < max_concurrency) and the queue is not empty,
#    the GenServer must immediately pull a job and run it asynchronously using
#    `Task.Supervisor.async_nolink/2` (monitored via process monitor).
# 4. When a job completes or crashes, the GenServer must receive a message
#    from the Task (in handle_info), decrement the running job count, and automatically
#    pull the next job from the queue to run (if any).
#
# Run this file with the command: elixir job_queue_practice.exs
# ==============================================================================

defmodule JobQueue do
  use GenServer

  # --- CLIENT API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds a job to the processing queue.
  """
  def enqueue(job_fun) do
    GenServer.call(__MODULE__, {:enqueue, job_fun})
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 2)

    state = %{
      max_concurrency: max_concurrency,
      # Use Erlang's :queue module to optimize the FIFO structure
      queue: :queue.new(),
      # Map to map Task ref => job_ref
      running_jobs: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, job_fun}, _from, state) do
    # Enqueue the job into the FIFO queue
    new_queue = :queue.in(job_fun, state.queue)
    new_state = %{state | queue: new_queue}

    # Trigger the check and start jobs if there are available slots
    final_state = process_queue(new_state)

    {:reply, :ok, final_state}
  end

  # Handle messages returned from Task.async_nolink on successful completion
  # Message format: {ref, result}
  @impl true
  def handle_info({ref, _result}, state) do
    # Stop monitoring this task ref
    Process.demonitor(ref, [:flush])

    # Remove the task from the running list
    new_running = Map.delete(state.running_jobs, ref)
    new_state = %{state | running_jobs: new_running}

    # Check and run the next job in the queue
    final_state = process_queue(new_state)

    {:noreply, final_state}
  end

  # Handle messages when a Task worker crashes or exits
  # Message format: {:DOWN, ref, :process, _pid, reason}
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Remove the task from the running list (in case of crash or termination)
    new_running = Map.delete(state.running_jobs, ref)
    new_state = %{state | running_jobs: new_running}

    # Check and run the next job in the queue
    final_state = process_queue(new_state)

    {:noreply, final_state}
  end

  # --- HELPER FUNCTIONS ---

  # Function to process the queue and spawn tasks if slots are available
  defp process_queue(state) do
    current_running = map_size(state.running_jobs)

    if current_running < state.max_concurrency do
      case :queue.out(state.queue) do
        {{:value, job_fun}, rest_queue} ->
          # Spawn task asynchronously without linking via Task.Supervisor
          task = Task.Supervisor.async_nolink(JobQueueSupervisor, job_fun)

          # Save the task ref in the running map to monitor
          new_running = Map.put(state.running_jobs, task.ref, true)

          # Recursively check if there are more available slots
          process_queue(%{state | queue: rest_queue, running_jobs: new_running})

        {:empty, _} ->
          # Queue is empty, return current state
          state
      end
    else
      # Max concurrency reached, do not spawn more
      state
    end
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule JobQueueTest do
  use ExUnit.Case
  @moduletag :capture_log

  setup do
    # Start Task.Supervisor to manage job processes
    start_supervised!({Task.Supervisor, name: JobQueueSupervisor})
    # Start JobQueue with a maximum concurrency limit of 2 jobs
    start_supervised!({JobQueue, max_concurrency: 2})
    :ok
  end

  test "runs at most max_concurrency jobs concurrently" do
    # Use an Agent to record the sequence and count of currently running jobs
    {:ok, tracker} = Agent.start_link(fn -> [] end)

    job_fun = fn id ->
      fn ->
        Agent.update(tracker, fn running -> running ++ [{:start, id}] end)
        # Simulating work
        Process.sleep(100)
        Agent.update(tracker, fn running -> running ++ [{:end, id}] end)
      end
    end

    # Enqueue 3 jobs
    JobQueue.enqueue(job_fun.(1))
    JobQueue.enqueue(job_fun.(2))
    JobQueue.enqueue(job_fun.(3))

    # Wait 50ms to ensure jobs 1 and 2 have started, while job 3 is queued
    Process.sleep(50)
    history = Agent.get(tracker, & &1)

    # Assert jobs 1 and 2 started, but job 3 has not
    assert {:start, 1} in history
    assert {:start, 2} in history
    refute {:start, 3} in history

    # Wait another 100ms for jobs 1 and 2 to finish, at which point job 3 is pulled and run
    Process.sleep(100)
    history2 = Agent.get(tracker, & &1)

    # Assert job 3 has started running
    assert {:start, 3} in history2

    # Wait for job 3 to complete
    Process.sleep(100)
    history3 = Agent.get(tracker, & &1)
    assert {:end, 3} in history3
  end

  test "automatically pulls new job from queue when previous job crashes" do
    {:ok, tracker} = Agent.start_link(fn -> [] end)

    normal_job = fn ->
      Agent.update(tracker, fn running -> running ++ [:normal_started] end)
    end

    crash_job = fn ->
      Agent.update(tracker, fn running -> running ++ [:crash_started] end)
      raise "Job crashed intentionally!"
    end

    # Enqueue 1 failing job and 2 normal jobs (max_concurrency = 2)
    JobQueue.enqueue(crash_job)
    JobQueue.enqueue(normal_job)
    JobQueue.enqueue(normal_job)

    # Wait for system processing
    Process.sleep(100)

    history = Agent.get(tracker, & &1)

    # Even if job 1 crashes, other jobs in the queue should still be pulled and run normally
    assert :crash_started in history
    assert count_occurrences(history, :normal_started) == 2
  end

  defp count_occurrences(list, item) do
    Enum.count(list, &(&1 == item))
  end
end
