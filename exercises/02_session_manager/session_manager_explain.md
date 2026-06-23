# 💡 Giải Thích Bài Tập: Dynamic Process Management (`Registry` & `DynamicSupervisor`)

## 1. Yêu Cầu Thực Tế & Thiết Kế
Trong các hệ thống phân phối lớn, thời gian thực (như chat rooms, user sessions, game sessions), chúng ta không thể lưu trữ liên tục trạng thái trên Database do tần suất đọc ghi quá dày đặc gây nghẽn I/O.
Giải pháp của Elixir là khởi chạy **mỗi User Session thành một Process (GenServer) riêng biệt**. 

Tuy nhiên, chúng ta không thể định nghĩa cứng các process này trong Supervision tree khi khởi động ứng dụng vì ta không biết trước user nào sẽ đăng nhập. Do đó ta cần:
1.  **DynamicSupervisor:** Để khởi chạy các worker process động tại runtime khi user đăng nhập.
2.  **Registry:** Làm danh bạ điện thoại để map chuỗi String `user_id` thành `PID` của process tương ứng nhằm gửi message tới đúng người.

---

## 2. Giải Thích Code Triển Khai

### 2.1. Định Danh Động Với Via Tuple
Để GenServer tự động đăng ký tên của nó vào Registry khi khởi động:
```elixir
def via_tuple(user_id) do
  {:via, Registry, {UserRegistry, user_id}}
end

def start_link(user_id) do
  # Đăng ký tên process bằng via tuple thay vì đăng ký atom tên module cứng
  GenServer.start_link(__MODULE__, %{}, name: via_tuple(user_id))
end
```
*   `{:via, Registry, {registry_name, key}}` là một định dạng chuẩn của BEAM VM. Khi bạn gửi message hoặc gọi hàm tới tuple này, BEAM sẽ tự động tra cứu trong Registry `UserRegistry` để tìm PID thực tế của `user_id` và chuyển message tới đó.

### 2.2. Triển Khai SessionManager

```elixir
defmodule SessionManager do
  # 1. Khởi chạy session mới động
  def start_session(user_id) do
    # Yêu cầu DynamicSupervisor tạo child worker
    case DynamicSupervisor.start_child(UserSessionSupervisor, {SessionWorker, user_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  # 2. Truy vấn dữ liệu từ session
  def get_session_data(user_id) do
    # Tra cứu danh bạ Registry để tìm PID của user_id
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> {:ok, SessionWorker.get_data(pid)}
      [] -> {:error, :not_found}
    end
  end

  # 3. Cập nhật dữ liệu session
  def update_session_data(user_id, key, value) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> {:ok, SessionWorker.put_data(pid, key, value)}
      [] -> {:error, :not_found}
    end
  end

  # 4. Tắt session (logout)
  def stop_session(user_id) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> 
        # Sử dụng DynamicSupervisor để chấm dứt process an toàn sạch sẽ
        DynamicSupervisor.terminate_child(UserSessionSupervisor, pid)
        :ok
      [] -> {:error, :not_found}
    end
  end
end
```

---

## 3. Các Điểm Quan Trọng Dưới Góc Nhìn Kỹ Thuật

### 3.1. Tại sao dùng `DynamicSupervisor.terminate_child/2` thay vì `GenServer.stop/1`?
*   Nếu bạn gọi `GenServer.stop(pid)`, process sẽ dừng lại. Tuy nhiên, nếu process đó được cấu hình với tùy chọn `restart: :permanent` (mặc định của supervisor), Supervisor sẽ nghĩ đây là một sự cố ngoài ý muốn và **lập tức khởi động lại** một worker session mới tinh. Điều này làm user không thể logout.
*   Gọi `DynamicSupervisor.terminate_child/2` giúp Supervisor nhận thức được đây là hành động chủ động gỡ bỏ child worker khỏi danh sách giám sát, tránh việc tự động restart vô hạn.
*   Đặt `restart: :transient` trong `SessionWorker` nghĩa là: process chỉ được restart nếu nó bị crash đột ngột (exit abnormal). Nếu nó hoàn thành nhiệm vụ và tắt bình thường (`:normal`), Supervisor sẽ để yên không restart.

### 3.2. Registry Tự Dọn Dẹp (Auto-cleanup)
*   Một tính năng cực kỳ mạnh mẽ của Registry trong Elixir là nó tự động giám sát (monitor) tất cả các process đăng ký tên trong nó.
*   Nếu một `SessionWorker` bị crash hoặc tắt đi do logout, Registry sẽ tự động nhận biết và xóa liên kết `{user_id => pid}` ra khỏi bảng tra cứu ngay lập tức. Chúng ta hoàn toàn không cần viết code thủ công để dọn dẹp Registry.
