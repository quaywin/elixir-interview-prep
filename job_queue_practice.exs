# ==============================================================================
# BÀI TẬP THỰC HÀNH NGÀY 1 (NÂNG CAO 2): CONCURRENT JOB QUEUE
# ==============================================================================
# Đề bài: Xây dựng một GenServer tên là `JobQueue` dùng để quản lý việc thực thi
# các công việc bất đồng bộ (jobs) với giới hạn số lượng công việc chạy đồng thời
# tối đa (max concurrency).
#
# Yêu cầu:
# 1. GenServer khởi chạy nhận tham số cấu hình:
#    - `max_concurrency`: Số lượng job tối đa được phép chạy đồng thời (ví dụ: 2 jobs).
# 2. Định nghĩa API client:
#    - `enqueue(job_fun)`: Thêm một job (dưới dạng một anonymous function) vào hàng đợi.
# 3. Khi có chỗ trống (số lượng job đang chạy < max_concurrency) và hàng đợi không trống,
#    GenServer phải lập tức lấy job ra và khởi chạy nó một cách bất đồng bộ sử dụng
#    `Task.Supervisor.async_nolink/2` (giám sát thông tin qua monitor).
# 4. Khi một job hoàn thành hoặc bị crash, GenServer phải nhận được message
#    từ Task (trong handle_info), giảm số lượng job đang chạy, và tự động kéo thêm
#    job mới từ hàng đợi ra chạy tiếp (nếu có).
#
# Chạy file này bằng lệnh: elixir job_queue_practice.exs
# ==============================================================================

defmodule JobQueue do
  use GenServer

  # --- CLIENT API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Thêm một job vào hàng đợi xử lý.
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
      queue: :queue.new(),       # Sử dụng :queue module Erlang để tối ưu cấu trúc FIFO
      running_jobs: %{}          # Map để map Task ref => job_ref
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, job_fun}, _from, state) do
    # Đưa job vào hàng đợi FIFO
    new_queue = :queue.in(job_fun, state.queue)
    new_state = %{state | queue: new_queue}
    
    # Kích hoạt hàm kiểm tra và khởi chạy job nếu còn slot trống
    final_state = process_queue(new_state)

    {:reply, :ok, final_state}
  end

  # Xử lý tin nhắn từ Task.async_nolink trả về khi hoàn thành thành công
  # Định dạng message: {ref, result}
  @impl true
  def handle_info({ref, _result}, state) do
    # Tắt monitor liên kết với task ref này
    Process.demonitor(ref, [:flush])
    
    # Xóa task khỏi danh sách đang chạy
    new_running = Map.delete(state.running_jobs, ref)
    new_state = %{state | running_jobs: new_running}
    
    # Kiểm tra để chạy job tiếp theo trong queue
    final_state = process_queue(new_state)
    
    {:noreply, final_state}
  end

  # Xử lý tin nhắn khi Task worker bị crash hoặc hoàn thành xong
  # Định dạng message: {:DOWN, ref, :process, _pid, reason}
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Xóa task khỏi danh sách đang chạy (trong trường hợp crash hoặc hoàn thành)
    new_running = Map.delete(state.running_jobs, ref)
    new_state = %{state | running_jobs: new_running}
    
    # Kiểm tra để chạy job tiếp theo trong queue
    final_state = process_queue(new_state)
    
    {:noreply, final_state}
  end

  # --- HELPER FUNCTIONS ---

  # Hàm xử lý duyệt queue và spawn task nếu còn trống slot
  defp process_queue(state) do
    current_running = map_size(state.running_jobs)

    if current_running < state.max_concurrency do
      case :queue.out(state.queue) do
        {{:value, job_fun}, rest_queue} ->
          # Spawn task bất đồng bộ không link qua Task.Supervisor
          task = Task.Supervisor.async_nolink(JobQueueSupervisor, job_fun)
          
          # Lưu ref của task vào running map để monitor
          new_running = Map.put(state.running_jobs, task.ref, true)
          
          # Đệ quy tiếp tục kiểm tra xem còn slot trống nữa không
          process_queue(%{state | queue: rest_queue, running_jobs: new_running})

        {:empty, _} ->
          # Hàng đợi trống, giữ nguyên state
          state
      end
    else
      # Đã đạt giới hạn tối đa concurrency, không spawn thêm
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
    # Khởi động Task.Supervisor phục vụ quản lý job processes
    start_supervised!({Task.Supervisor, name: JobQueueSupervisor})
    # Khởi động JobQueue với giới hạn concurrency tối đa là 2 jobs
    start_supervised!({JobQueue, max_concurrency: 2})
    :ok
  end

  test "chỉ chạy song song tối đa max_concurrency jobs" do
    # Sử dụng Agent để ghi nhận thứ tự và số lượng job đang chạy thực tế
    {:ok, tracker} = Agent.start_link(fn -> [] end)
    
    job_fun = fn id ->
      fn ->
        Agent.update(tracker, fn running -> running ++ [{:start, id}] end)
        Process.sleep(100) # Simulating work
        Agent.update(tracker, fn running -> running ++ [{:end, id}] end)
      end
    end

    # Đưa vào 3 jobs
    JobQueue.enqueue(job_fun.(1))
    JobQueue.enqueue(job_fun.(2))
    JobQueue.enqueue(job_fun.(3))

    # Đợi 50ms để chắc chắn job 1 và 2 đã khởi chạy, nhưng job 3 phải xếp hàng
    Process.sleep(50)
    history = Agent.get(tracker, & &1)
    
    # Xác thực job 1 và 2 đã start, nhưng job 3 chưa start
    assert {:start, 1} in history
    assert {:start, 2} in history
    refute {:start, 3} in history

    # Đợi thêm 100ms nữa để job 1 và 2 kết thúc, lúc này job 3 mới được kéo ra chạy
    Process.sleep(100)
    history2 = Agent.get(tracker, & &1)
    
    # Xác thực job 3 đã bắt đầu chạy
    assert {:start, 3} in history2
    
    # Đợi job 3 chạy xong
    Process.sleep(100)
    history3 = Agent.get(tracker, & &1)
    assert {:end, 3} in history3
  end

  test "tự động kéo job mới từ queue khi job trước đó bị crash" do
    {:ok, tracker} = Agent.start_link(fn -> [] end)

    normal_job = fn ->
      Agent.update(tracker, fn running -> running ++ [:normal_started] end)
    end

    crash_job = fn ->
      Agent.update(tracker, fn running -> running ++ [:crash_started] end)
      raise "Job crashed intentionally!"
    end

    # Đưa vào 1 job lỗi và 2 job bình thường (max_concurrency = 2)
    JobQueue.enqueue(crash_job)
    JobQueue.enqueue(normal_job)
    JobQueue.enqueue(normal_job)

    # Đợi hệ thống xử lý
    Process.sleep(100)

    history = Agent.get(tracker, & &1)
    
    # Dù job 1 bị crash, các job còn lại trong hàng đợi vẫn được kéo ra chạy bình thường
    assert :crash_started in history
    assert count_occurrences(history, :normal_started) == 2
  end

  defp count_occurrences(list, item) do
    Enum.count(list, &(&1 == item))
  end
end
