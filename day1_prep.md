# 📔 Ngày 1: Kiến Trúc BEAM VM, OTP Internals & Cơ Chế Cơ Sở Dữ Liệu (Ecto)

Tài liệu này không cung cấp các câu trả lời ngắn để học thuộc lòng. Nó giải thích **bản chất cơ học (how it works under the hood)** và **lý do thiết kế (why it was designed this way)** của BEAM VM, OTP và Ecto để giúp bạn có tư duy hệ thống của một Senior Engineer.

---

## 1. Cơ Chế Hoạt Động Của BEAM VM (Erlang Run-Time System - ERTS)

### 1.1. Luồng Lập Lịch (Preemptive Scheduling Mechanics)
Trong hầu hết các hệ điều hành và ngôn ngữ lập trình (như Go hay NodeJS), lập lịch là **Cooperative (Cộng tác)**. Tức là một luồng (thread/goroutine) phải chủ động nhường quyền (yield) khi gặp các lệnh I/O hoặc gọi hàm đặc biệt để luồng khác được chạy. Nếu bạn viết một vòng lặp vô hạn tính toán toán học, nó sẽ chặn hoàn toàn thread đó.

BEAM VM giải quyết vấn đề này bằng **Preemptive Scheduling (Lập lịch phân thì/chiếm quyền)** dựa trên khái niệm **Reductions**:

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
       | 1. Lấy Process A ra chạy
       v
+-------------------------------------------------------------------+
| Execute: Process A                                                |
| - Mỗi hàm gọi, phép toán, gửi message = 1 Reduction               |
| - Giới hạn tối đa (Budget): 2000 Reductions                       |
+-------------------------------------------------------------------+
       |
       | 2. Khi tiêu thụ hết 2000 Reductions (hoặc bị block bởi I/O)
       v
+-------------------------------------------------------------------+
| Context Switch:                                                   |
| - Lưu Program Counter (PC) và thanh ghi của Process A             |
| - Đẩy Process A xuống cuối Run Queue                              |
| - Lấy Process B lên chạy tiếp                                     |
+-------------------------------------------------------------------+
```

*   **Reduction là gì?** Nó là một đơn vị đo lường công việc của BEAM VM. Mỗi lần gọi hàm, thực thi một BIF (Built-in Function), hay thực hiện một phép so sánh pattern matching đều tiêu tốn reductions.
*   **Context Switch trong BEAM siêu nhẹ:** Khác với hệ điều hành (phải chuyển đổi không gian địa chỉ ảo, flush Page Table, chuyển từ User Mode sang Kernel Mode), BEAM Process chỉ là một cấu trúc dữ liệu trong user-space. Context switch chỉ đơn giản là lưu trữ vài thanh ghi con trỏ (Stack Pointer, Program Counter) vào vùng nhớ PCB (Process Control Block) của process đó. Chi phí này mất chưa đến vài nano-giây.
*   **Work Stealing:** Mỗi CPU Core vật lý có 1 Scheduler Thread quản lý 1 Run Queue riêng. Nếu Run Queue của Scheduler 1 trống, nó sẽ khóa (lock) và "ăn trộm" (steal) một số process từ cuối Run Queue của Scheduler 2 để đảm bảo tất cả các core đều hoạt động đồng đều, tối ưu hóa phần cứng đa nhân.

---

### 1.2. Kiến Trúc Bộ Nhớ & Garbage Collection (GC)
Để hiểu tại sao BEAM VM không bao giờ bị hiện tượng "Stop-the-world" (toàn bộ ứng dụng dừng lại để dọn rác như Java), chúng ta cần nhìn vào cấu trúc bộ nhớ của từng Process:

```
+-----------------------------------------------------------------------+
| BEAM Process Memory Layout                                            |
|                                                                       |
|  +-----------------------------------------------------------------+  |
|  | Process Control Block (PCB)                                     |  |
|  | - Pid, Status, Mailbox pointers, Links/Monitors list            |  |
|  +-----------------------------------------------------------------+  |
|  | Stack (Lớn dần từ trên xuống)                                   |  |
|  | - Chứa biến cục bộ, đối số hàm, địa chỉ quay lại (return)       |  |
|  |            |                                                    |  |
|  |            v                                                    |  |
|  |                                                                 |  |
|  |            ^                                                    |  |
|  |            |                                                    |  |
|  | Heap (Lớn dần từ dưới lên)                                      |  |
|  | - Chứa Tuples, Lists, Maps, Heap Binaries (< 64 bytes)          |  |
|  +-----------------------------------------------------------------+  |
|                                                                       |
+-----------------------------------------------------------------------+
```

*   **Tại sao lại dùng Private Heap (Bộ nhớ riêng)?**
    *   **Không có lock contention:** Vì mỗi process sở hữu vùng bộ nhớ riêng, nó không cần xin khóa (mutex lock) để cấp phát bộ nhớ mới. Việc cấp phát chỉ đơn giản là tăng con trỏ Heap Pointer (Bumping allocator), cực kỳ nhanh.
    *   **GC độc lập:** GC chỉ chạy trên Heap của duy nhất process đang bị thiếu bộ nhớ. 99% các process khác vẫn chạy bình thường.
    *   **Cái giá phải trả (Trade-off):** Khi gửi message giữa Process A và Process B, dữ liệu bắt buộc phải được **sao chép (deep copy)** từ Heap của A sang Heap của B. Việc này tốn chi phí CPU nếu message có kích thước lớn.
*   **Cơ chế Generational GC (GC theo thế hệ):**
    *   **Young Heap (Thế hệ mới):** Hầu hết các biến trong lập trình hàm có vòng đời rất ngắn. Khi dọn rác ở Young Heap, BEAM dùng thuật toán *Copying Collector*. Nó quét các biến còn sống từ Stack, sao chép chúng sang một vùng nhớ mới tinh (To-space) nằm liền kề nhau để chống phân mảnh, sau đó giải phóng toàn bộ vùng nhớ cũ (From-space).
    *   **Old Heap (Thế hệ cũ):** Nếu một biến sống sót qua nhiều lần Minor GC, nó được "thăng cấp" (promoted) chuyển sang Old Heap. Khi Old Heap đầy, Major GC mới chạy với thuật toán *Sweep* (chi phí cao hơn).
*   **Cơ chế lưu trữ Binary (Off-heap Binaries):**
    *   Nếu lưu một chuỗi HTML 5MB trên Heap của Process A, khi gửi sang Process B sẽ mất 5MB bộ nhớ và tốn thời gian copy.
    *   **Giải pháp của BEAM:** Bất kỳ binary nào **> 64 bytes** (gọi là *Refc Binary*) được lưu trữ ở **Global Shared Heap** ngoài các process.
    *   Trên Heap của Process A và B lúc này chỉ chứa một **ProcBin** (24 bytes) gồm con trỏ trỏ tới vùng nhớ Global đó và dung lượng của nó.
    *   **Rò rỉ bộ nhớ với Sub-binaries:** Khi bạn parse một chuỗi JSON khổng lồ 20MB, lấy ra một token nhỏ `"user_123"` (18 bytes). Nếu bạn giữ token này trong state của GenServer, do nó là một lát cắt (slice) của binary gốc, nó vẫn giữ tham chiếu tới toàn bộ khối 20MB kia. Hệ thống sẽ không thể giải phóng 20MB này khỏi Global Heap.
    *   *Cách khắc phục:* Gọi `:binary.copy("user_123")`. Hàm này sẽ copy chuỗi 18 bytes đó vào trực tiếp Heap nội bộ của process (dưới dạng Heap Binary vì < 64 bytes) và ngắt kết nối với khối 20MB ban đầu, cho phép GC dọn dẹp khối 20MB kia.

---

## 2. Bản Chất Hóa Học Của OTP (Open Telecom Platform)

### 2.1. GenServer Thực Chất Là Gì?
Đừng nghĩ GenServer là một class hay một magic component. Dưới góc độ BEAM, một GenServer thực chất là một **Erlang Process chạy một vòng lặp đệ quy đuôi vô hạn (infinite tail-recursive loop)**:

```elixir
defmodule MyGenServer do
  # Hàm khởi chạy process
  def start_link(init_arg) do
    spawn_link(fn -> loop(init_arg) end)
  end

  # Vòng lặp nhận tin nhắn
  defp loop(state) do
    receive do
      {:call, from, :get_state} ->
        send(from, {:reply, state})
        loop(state) # Tiếp tục đệ quy để giữ process sống

      {:cast, {:update, new_val}} ->
        new_state = process_update(state, new_val)
        loop(new_state) # Cập nhật state mới cho vòng lặp tiếp theo
    end
  end
end
```

*   **Mailbox (Hộp thư):** Mỗi process có một hàng đợi tin nhắn là một Single Linked List. Khi bạn gửi message tới process, message được chép vào cuối list này.
*   **Selective Receive (Nhận chọn lọc):** Khi lệnh `receive` chạy, BEAM sẽ duyệt từ đầu Mailbox để tìm tin nhắn khớp với pattern. Nếu tin nhắn không khớp, nó sẽ được đưa vào một hàng đợi tạm thời (save queue). Nếu Mailbox của bạn tích tụ hàng triệu tin nhắn không khớp, BEAM sẽ phải duyệt qua hàng triệu phần tử mỗi khi có tin nhắn mới đến, gây sụt giảm hiệu năng nghiêm trọng.
*   **Tại sao `init` lại blocking?** Khi Supervisor gọi `start_link`, nó sử dụng cơ chế đồng bộ (`GenServer.start_link`). Supervisor process sẽ block hoàn toàn để chờ phản hồi từ hàm `init/1` của child process. Nếu `init/1` gọi API bên ngoài mất 10 giây, toàn bộ quá trình boot của ứng dụng sẽ bị treo, dẫn đến Supervisor tự crash do vượt quá thời gian timeout (thường là 5000ms).
*   **Cơ chế `handle_continue`:**
    ```
    Supervisor gọi start_link() -> Chạy init() 
                                      | (Trả về {:ok, state, {:continue, :step}})
                                      v
    Supervisor nhận ok, giải phóng block (App tiếp tục boot)
                                      |
                                      v
    GenServer lập tức tự gửi message {:continue, :step} cho chính nó
    (Tin nhắn này được chèn vào đầu Mailbox, chạy trước mọi request từ bên ngoài)
                                      |
                                      v
                               Chạy handle_continue()
    ```

---

### 2.2. Tránh Bottleneck (Nghẽn cổ chai)
Vì GenServer xử lý tin nhắn trong Mailbox theo cơ chế **tuần tự (FIFO - First In First Out)** trên một luồng duy nhất, nếu bạn có 10,000 requests/giây gọi tới cùng một GenServer để đọc thông tin cấu hình, các request sẽ xếp hàng dài trong Mailbox, gây tăng latency.

#### Giải pháp 1: ETS (Erlang Term Storage) - Đọc/Ghi Song Song
ETS là một storage engine in-memory được viết bằng C trực tiếp trong Erlang runtime.
*   Nó cho phép bất kỳ process nào cũng có thể đọc trực tiếp dữ liệu mà không cần gửi message qua GenServer (tránh serialize/deserialize dữ liệu qua mailbox).
*   **Mô hình thiết kế chuẩn:** Một GenServer đóng vai trò là "writer" (nhận ghi dữ liệu, ghi xuống ETS). Các Web Controller đóng vai trò là các "reader" (đọc trực tiếp từ ETS table bằng `:ets.lookup/2`). Điều này giúp tăng throughput lên hàng trăm ngàn requests/giây vì các thao tác đọc chạy song song hoàn toàn.

#### Giải pháp 2: PartitionSupervisor
Nếu bạn bắt buộc phải thực hiện các tác vụ ghi/xử lý logic có state:
*   `PartitionSupervisor` sẽ khởi chạy một nhóm (pool) gồm $N$ GenServer con.
*   Khi có request, hệ thống sẽ hash một key (ví dụ: `user_id`) để xác định request đó sẽ gửi tới worker số mấy. Điều này chia tải (load balance) đều ra các process khác nhau, giải quyết triệt để bottleneck.

---

## 3. Bản Chất Truy Vấn Của Ecto & PostgreSQL

### 3.1. Ecto.Multi Hoạt Động Như Thế Nào?
Nhiều kỹ sư nhầm tưởng `Ecto.Multi` lập tức mở transaction và khóa database khi bạn viết code. Thực tế:
*   `Ecto.Multi` chỉ là một **công cụ xây dựng cấu trúc dữ liệu thuần túy (Pure Data Structure Builder)**. Khi bạn gọi `Ecto.Multi.new() |> Ecto.Multi.run(...)`, bạn chỉ đang xây dựng một danh sách các câu lệnh/hàm dạng mô tả (declarative). Hoàn toàn không có kết nối nào tới DB được mở ở bước này.
*   Chỉ khi bạn gọi `Repo.transaction(multi)`, Ecto mới:
    1. Lấy một DB Connection từ Pool.
    2. Bắt đầu câu lệnh `BEGIN` mở Transaction thực sự trong Postgres.
    3. Chạy tuần tự từng bước trong Multi.
    4. Nếu tất cả thành công, gọi `COMMIT`.
    5. Nếu có bất kỳ bước nào lỗi (trả về `{:error, reason}`), Ecto lập tức phát lệnh `ROLLBACK` để khôi phục toàn bộ trạng thái DB về ban đầu và trả kết nối lại cho Pool.

### 3.2. N+1 Queries: Cơ Chế Cơ Học
Giả sử bạn có 100 User, mỗi User có nhiều Order. Bạn muốn in ra tên User kèm danh sách Order.

*   **Cách viết lỗi (N+1):**
    ```elixir
    users = Repo.all(User) # 1 truy vấn lấy 100 users
    Enum.each(users, fn user ->
      orders = Repo.all(assoc(user, :orders)) # 100 truy vấn lấy orders cho từng user
      IO.inspect({user.name, orders})
    end)
    ```
    *Cơ chế:* 101 lần gọi mạng tới PostgreSQL. Tổng thời gian trễ (latency) = 101 * Roundtrip time (RTT). Nếu RTT = 5ms, bạn mất ít nhất 500ms chỉ để chờ mạng.

*   **Cách xử lý với Preload (2 Queries):**
    ```elixir
    users = Repo.all(User) |> Repo.preload(:orders)
    ```
    *Cơ chế cơ học:* Ecto chạy câu truy vấn 1: `SELECT * FROM users;`. Ecto gom toàn bộ các ID của users vừa lấy được (ví dụ: `[1, 2, 3, ..., 100]`). Sau đó nó chạy câu truy vấn 2: `SELECT * FROM orders WHERE user_id IN (1, 2, 3, ..., 100);`. Cuối cùng, Ecto tự thực hiện mapping các bản ghi Order về đúng struct User trong RAM của ứng dụng. Chỉ tốn 2 lần RTT (10ms).

*   **Cách xử lý với Join (1 Query):**
    ```elixir
    query = from u in User,
              join: o in assoc(u, :orders),
              preload: [orders: o]
    users = Repo.all(query)
    ```
    *Cơ chế cơ học:* Chỉ có 1 câu truy vấn được gửi tới DB sử dụng `INNER JOIN` hoặc `LEFT OUTER JOIN`. Postgres sẽ thực hiện việc liên kết dữ liệu ở tầng đĩa cứng/bộ nhớ của nó và trả về một tập kết quả phẳng (flat result set) duy nhất. Ecto parse tập kết quả này để dựng lại các struct lồng nhau. Phù hợp khi bạn cần lọc User dựa trên điều kiện của Order (ví dụ: tìm User có đơn hàng lớn hơn 1 triệu).

---

## 🚀 Các bài tập thực hành Ngày 1 (exercises/)
*   **[01_ledger]**: Giao dịch Ecto.Multi an toàn. -> [Bài tập](exercises/01_ledger/ledger_practice.exs) | [Giải thích](exercises/01_ledger/ledger_explain.md)
*   **[02_session_manager]**: Quản lý Dynamic Process (DynamicSupervisor + Registry). -> [Bài tập](exercises/02_session_manager/session_manager_practice.exs) | [Giải thích](exercises/02_session_manager/session_manager_explain.md)
*   **[03_job_queue]**: Hàng đợi công việc đồng thời (Task.Supervisor + Monitor). -> [Bài tập](exercises/03_job_queue/job_queue_practice.exs) | [Giải thích](exercises/03_job_queue/job_queue_explain.md)
*   **[04_write_through_cache]**: Thiết kế Write-Through Cache với bảng ETS. -> [Bài tập](exercises/04_write_through_cache/write_through_cache_practice.exs) | [Giải thích](exercises/04_write_through_cache/write_through_cache_explain.md)
*   **[07_algorithms]**: Cấu trúc dữ liệu & Thuật toán giải bằng lập trình hàm Elixir. -> [Bài tập](exercises/07_algorithms/algorithm_practice.exs) | [Cẩm nang](exercises/07_algorithms/algorithm_tricks.md)
