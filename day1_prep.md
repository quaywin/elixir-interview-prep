# 📔 Ngày 1: Core OTP, BEAM Internals & Ecto Optimizations

## 1. BEAM VM & OTP Internals

### Process Scheduling (Preemptive)
*   **Cách hoạt động:** BEAM VM chạy một Scheduler trên mỗi CPU core. Mỗi scheduler quản lý một run queue chứa các Erlang processes.
*   **Cơ chế:** Khác với cooperative scheduling, BEAM dùng **Preemptive Scheduling** dựa trên **reduction count** (mỗi hàm gọi hoặc thao tác tính toán tương đương với 1 reduction). Một process được chạy tối đa **2000 reductions** thì scheduler sẽ tạm dừng nó (preempt) và chuyển sang process tiếp theo. Điều này giúp đảm bảo tính Real-time/Soft Real-time: không một process đơn lẻ nào có thể chiếm quyền CPU quá lâu làm nghẽn hệ thống (ngăn ngừa latency spike).

### Garbage Collection (Per-process Heap)
*   **Cách hoạt động:** Mỗi process trong BEAM có vùng nhớ Heap riêng độc lập. GC chạy độc lập trên từng process heap này.
*   **Ưu điểm:** 
    *   Không có hiện tượng "stop-the-world" (toàn bộ ứng dụng dừng lại để GC dọn rác) như Java hay Go. GC chỉ lock và dọn dẹp vùng nhớ của một process cụ thể khi process đó cần thêm bộ nhớ hoặc kết thúc nhiệm vụ.
    *   Khi một process chết đi, toàn bộ heap của nó được giải phóng ngay lập tức mà không cần chạy GC algorithm phức tạp.

### Fault Tolerance & Supervision Trees
*   **Triết lý:** "Let it crash". Thay vì viết quá nhiều code try-catch phòng ngừa mọi lỗi có thể xảy ra, hãy để process crash và để Supervisor khôi phục nó về trạng thái an toàn đã biết.
*   **Supervision Strategies:**
    *   `one_for_one`: Phù hợp nhất cho các dynamic workers không phụ thuộc trạng thái lẫn nhau. Khi worker crash, chỉ duy nhất nó được restart.
    *   `one_for_all`: Dùng khi các process phụ thuộc chặt chẽ vào nhau (ví dụ: một process đọc kết nối mạng và một process xử lý dữ liệu từ kết nối đó). Nếu một đứa crash, restart toàn bộ.
    *   `rest_for_one`: Nếu process A crash, các process khởi tạo sau nó trong supervisor child list (B, C, D) sẽ bị tắt và khởi động lại. Các process khởi tạo trước A không bị ảnh hưởng.
    *   `DynamicSupervisor`: Cho phép giám sát các child process được tạo ra động tại runtime (ví dụ: tạo 1 process xử lý giao dịch cho mỗi user đăng nhập).

---

## 2. GenServer Lifecycle & State

### Các callback cốt lõi và vai trò
1.  `init(init_arg)`: Khởi tạo state. Chú ý: callback này là **blocking**. Nếu bạn gọi API bên ngoài hoặc truy vấn DB nặng ở đây, nó sẽ làm nghẽn quá trình khởi động ứng dụng (hoặc làm Supervisor bị timeout). 
    *   *Giải pháp:* Trả về `{:ok, state, {:continue, :post_init}}` và xử lý logic nặng trong callback `handle_continue/2`.
2.  `handle_call(msg, from, state)`: Xử lý các request đồng bộ (synchronous). Bắt buộc trả về phản hồi (`{:reply, reply, new_state}`). Làm block caller cho đến khi nhận được kết quả.
3.  `handle_cast(msg, state)`: Xử lý request bất đồng bộ (asynchronous). Trả về `{:noreply, new_state}`. Không block caller.
4.  `handle_info(msg, state)`: Xử lý tất cả các message "ngoài luồng" gửi trực tiếp đến PID của GenServer bằng toán tử `send/2` thay vì qua hàm của module GenServer (ví dụ: `:erlang.send_after/3` phát timer, message từ cổng mạng hoặc sự kiện `:DOWN` từ process khác đang được monitor).

### ❓ Câu hỏi phỏng vấn thực tế:
*   **Q:** Làm thế nào để lưu trữ trạng thái giữa các lần khởi động lại GenServer?
    *   **A:** Bản thân GenServer lưu state trong bộ nhớ in-memory của process, nếu crash thì state mất sạch. Để khôi phục state, ta phải ghi state xuống một database (PostgreSQL/Redis) hoặc sử dụng ETS table có owner process khác (không bị crash cùng GenServer). Khi khởi động lại (`init`), GenServer sẽ đọc lại dữ liệu từ các nguồn này.
*   **Q:** Phân biệt `Task.async/1` và `Task.start/1`?
    *   **A:** 
        *   `Task.async/1` trả về một `%Task{}` struct và tự động link với process hiện tại. Nó được thiết kế để bạn đợi kết quả trả về bằng cách dùng `Task.await/2`. Nếu task crash, caller process cũng crash theo.
        *   `Task.start/1` khởi chạy một process bất đồng bộ dạng fire-and-forget, không link với caller process. Bạn không cần (và không thể) đợi kết quả của nó.

---

## 3. Phoenix & Ecto Optimizations

### Tối ưu hóa truy vấn Database
1.  **N+1 Query Problem:** Xảy ra khi bạn load danh sách bản ghi (ví dụ: 100 Posts), sau đó lặp qua từng bản ghi để load các bản ghi liên quan (ví dụ: load Comment của từng Post). Kết quả là tạo ra 1 + 100 câu truy vấn DB.
    *   *Cách xử lý:* Sử dụng `Repo.preload/2` hoặc `join` trực tiếp trong query để Ecto thực hiện preloading thông minh bằng một vài câu SQL gọn nhẹ.
2.  **Ecto.Multi:** 
    *   Giúp gom nhiều thao tác database vào một database transaction duy nhất.
    *   Cho phép kết hợp kết quả của bước trước làm input cho bước sau (ví dụ: lấy ID của User vừa tạo ở bước 1 để tạo Ví ở bước 2).
    *   Nếu bất kỳ bước nào trong `Multi` thất bại, toàn bộ các bước trước đó sẽ được rollback tự động.

### ❓ Câu hỏi phỏng vấn thực tế:
*   **Q:** Bạn dùng công cụ nào để phát hiện các câu query chậm trong production?
    *   **A:** Sử dụng thư viện `:telemetry` thu thập metrics thực thi của Ecto, kết hợp với Prometheus/Grafana để vẽ đồ thị latency. Trong môi trường local, sử dụng `Phoenix LiveDashboard` mục Ecto stats để xem trực tiếp các slow queries.
*   **Q:** Làm thế nào để thực hiện khóa dòng (Row locking / Pessimistic locking) trong Ecto?
    *   **A:** Sử dụng hàm `lock/2` trong query builder, ví dụ: `from(a in Account, where: a.id == ^id, lock: "FOR UPDATE")`. Việc này ngăn chặn race conditions khi nhiều process cùng lúc muốn cập nhật số dư của một tài khoản.

---

## 🚀 Thử thách thực hành Ngày 1
Hãy mở file [ledger_practice.exs](ledger_practice.exs) và hoàn thành các bài tập liên quan đến **Ecto.Multi** và **Concurrency locking**.
