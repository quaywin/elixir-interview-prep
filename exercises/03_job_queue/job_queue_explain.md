# 💡 Giải Thích Bài Tập: Concurrent Job Queue (`Task.Supervisor` & `Monitor`)

## 1. Yêu Cầu Thực Tế & Thiết Kế
Trong các hệ thống lớn, chúng ta thường cần xử lý các tác vụ nền song song (gọi API của bên thứ ba, nén ảnh, xử lý dữ liệu) nhưng phải giới hạn số lượng công việc chạy đồng thời (`max_concurrency`). 
Nếu không giới hạn, việc spawn hàng triệu process đồng loạt sẽ làm quá tải RAM hoặc làm nghẽn kết nối mạng và cơ sở dữ liệu.

Chúng ta cần xây dựng một GenServer đóng vai trò điều phối (`JobQueue`):
1.  Lưu trữ danh sách các công việc chờ xử lý trong cấu trúc dữ liệu hàng đợi.
2.  Theo dõi số lượng worker đang hoạt động.
3.  Khi một worker hoàn thành xong hoặc bị lỗi, GenServer phải lập tức nhận biết để kéo thêm công việc mới ra chạy tiếp.

---

## 2. Giải Thích Code Triển Khai

### 2.1. Cấu Trúc FIFO Queue của Erlang
Thay vì sử dụng List của Elixir (vì List trong Elixir là Linked List, việc lấy phần tử ở cuối hoặc thêm vào cuối tốn chi phí $O(N)$), chúng ta sử dụng module Erlang `:queue`.
*   `:queue.new()`: Khởi tạo hàng đợi trống.
*   `:queue.in(item, queue)`: Thêm một phần tử vào cuối hàng đợi (chi phí $O(1)$).
*   `:queue.out(queue)`: Lấy một phần tử ở đầu hàng đợi ra (chi phí $O(1)$).

### 2.2. Khởi Chạy Tác Vụ Bất Đồng Bộ Với `async_nolink`
```elixir
task = Task.Supervisor.async_nolink(JobQueueSupervisor, job_fun)
```
*   **Tại sao dùng `async_nolink`?** Nếu dùng `Task.Supervisor.async/2`, nó sẽ liên kết (link) hai process lại với nhau. Nếu worker task bị crash đột ngột (lỗi cú pháp, API timeout), nó sẽ kéo sập luôn cả GenServer `JobQueue` trung tâm. Dùng `async_nolink` giúp cô lập lỗi: worker crash thì mặc kệ nó, GenServer chính vẫn sống bình thường.
*   **Monitor hoạt động thế nào?** Hàm `async_nolink` tự động thiết lập một `monitor` từ GenServer tới task process mới tạo và trả về một `%Task{ref: ref}`. Khi task process này kết thúc hoặc bị crash, BEAM VM sẽ tự động gửi một message có định dạng `:DOWN` vào mailbox của GenServer.

### 2.3. Xử Lý Tin Nhắn Trạng Thái Của Task

```elixir
# 1. Khi Task hoàn thành thành công
def handle_info({ref, _result}, state) do
  # Tắt monitor liên kết với ref này để tránh nhận message :DOWN thừa
  Process.demonitor(ref, [:flush])
  
  # Dọn dẹp danh sách đang chạy và chạy tiếp job mới
  new_running = Map.delete(state.running_jobs, ref)
  final_state = process_queue(%{state | running_jobs: new_running})
  {:noreply, final_state}
end

# 2. Khi Task bị crash hoặc bị tắt đột ngột
def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
  new_running = Map.delete(state.running_jobs, ref)
  final_state = process_queue(%{state | running_jobs: new_running})
  {:noreply, final_state}
end
```

*   **Tại sao cần `Process.demonitor(ref, [:flush])`?** Khi task hoàn thành bình thường, nó gửi kết quả `{ref, result}`. Do ta đã monitor nó, sau khi gửi kết quả nó sẽ tắt đi, dẫn đến một tin nhắn `:DOWN` tiếp tục được gửi vào mailbox của GenServer. Gọi `Process.demonitor` kèm tùy chọn `[:flush]` giúp hủy theo dõi và dọn sạch tin nhắn `:DOWN` thừa này khỏi mailbox ngay lập tức.

---

## 3. Bản Chất Cơ Học Luồng Điều Phối
```
[Client] ---> Gọi JobQueue.enqueue(job)
                  |
                  v
       Ghi nhận vào :queue.in
                  |
                  v
       Gọi process_queue()
                  |
        +---------+---------+ (Số job đang chạy < max_concurrency?)
        | YES               | NO
        v                   v
 Spawn Task worker       Chờ trong queue
 Thiết lập monitor
        |
        v
 Worker hoàn thành / crash
        |
        v
 Gửi message {:DOWN, ref} tới JobQueue
        v
 Xử lý giải phóng slot -> Gọi lại process_queue() để kéo job tiếp theo
```
