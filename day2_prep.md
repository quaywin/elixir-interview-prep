# 📔 Ngày 2: Hệ Thống Phân Tán, Broadway Backpressure, Observability & Kiến Trúc Thiết Kế

Tài liệu này tập trung giải thích **nguyên lý cơ học (underlying principles)** và **phương án kiến trúc (architectural choices)** để giúp bạn trả lời các câu hỏi System Design và DevOps dưới góc nhìn của một Senior/Lead Engineer.

---

## 1. Bản Chất Phân Tán Trong Elixir (Distributed Elixir under the hood)

### 1.1. Erlang Distribution Protocol hoạt động như thế nào?
Khi bạn kết nối 2 node Elixir (`node1@10.0.0.1` và `node2@10.0.0.2`):

```
+-------------------+                      +-------------------+
|  node1@10.0.0.1   |                      |  node2@10.0.0.2   |
|                   |                      |                   |
|   +-----------+   |                      |   +-----------+   |
|   | Process A |   |                      |   | Process B |   |
|   +-----------+   |                      |   +-----------+   |
|         |         |                      |         ^         |
|         | send(PidB, msg)                |         |         |
|         v         |                      |         |         |
|   +-----------+   |    Erlang Proto      |   +-----------+   |
|   |   disterl |===|======================|==>|   disterl |   |
|   +-----------+   |  TCP Port (dynamic)  |   +-----------+   |
|         |         |                      |         |         |
|   +-----------+   |                      |   +-----------+   |
|   |   EPMD    |   |                      |   |   EPMD    |   |
|   | (Port 4369|   |                      |   | (Port 4369|   |
+---+-----------+---+                      +---+-----------+---+
```

1.  **EPMD (Erlang Port Mapper Daemon):** Là một service chạy ngầm ở port mặc định **4369** trên mỗi máy chủ. EPMD hoạt động giống như một DNS nội bộ cho các node Erlang. Khi `node1` muốn kết nối tới `node2`, nó sẽ hỏi EPMD của `node2`: *"Node tên là node2 đang chạy ở TCP port nào trên OS?"*. EPMD trả về port thực tế (ví dụ: port 58921 được sinh ngẫu nhiên khi node khởi động).
2.  **TCP Connection:** Hai node thiết lập một kết nối TCP duy nhất trực tiếp giữa chúng cho tất cả các hoạt động giao tiếp. Dữ liệu tin nhắn gửi qua lại giữa các process được tự động tuần tự hóa (serialized) sang định dạng nhị phân Erlang (External Term Format) bởi BEAM VM, hoàn toàn trong suốt với lập trình viên.
3.  **Toàn Kết Nối (Full Mesh Topology):** Mặc định, các node trong Erlang cluster kết nối theo dạng lưới (Node A kết nối B, B kết nối C -> A sẽ tự động kết nối C). 
    *   *Giới hạn vật lý:* Khi số lượng node tăng lên ($N > 40$), số lượng kết nối TCP chéo nhau ($N \times (N-1) / 2$) sẽ tăng vọt, gây nghẽn băng thông mạng chỉ để duy trì các gói tin heartbeat kiểm tra trạng thái sống của nhau.
    *   *Giải pháp:* Cho các hệ thống cực lớn, ta cấu hình `-connect_all false` để tự quản lý kết nối thủ công.

---

### 1.2. Horde & CRDTs (Conflict-Free Replicated Data Types)
Khi quản lý state phân tán, các hệ thống truyền thống thường sử dụng mô hình Master-Slave hoặc sử dụng database làm nguồn chân lý duy nhất (Single source of truth) có khóa (locking). Tuy nhiên, việc này làm giảm khả năng chịu lỗi và tăng độ trễ.

`Horde` giải quyết bài toán này bằng cách sử dụng **CRDTs (Delta-CRDTs)**:
*   **CRDT là gì?** Nó là một cấu trúc dữ liệu được thiết kế đặc biệt để có thể sao chép ra nhiều node khác nhau. Các node có thể cập nhật dữ liệu độc lập mà không cần xin phép node khác (không cần lock). Khi các node giao tiếp lại với nhau, các bản cập nhật sẽ được tự động hợp nhất (merge) theo một công thức toán học đảm bảo mọi node cuối cùng sẽ có cùng một kết quả giống hệt nhau (Eventual Consistency), bất kể thứ tự nhận các bản cập nhật là gì.
*   **Horde.Registry hoạt động ra sao?** Khi bạn đăng ký process `{:via, Horde.Registry, {MyRegistry, "user_123"}}` ở Node 1, Horde sẽ ghi nhận và đồng bộ sự tồn tại này sang Node 2 qua mạng bằng CRDT. Nếu Node 2 cố tình start một process trùng tên `"user_123"`, Horde sẽ phát hiện xung đột và tự động tắt bớt một process để đảm bảo tính duy nhất.
*   **Horde.DynamicSupervisor hoạt động ra sao?** Khi Node 1 chết, các node còn lại nhận thấy sự vắng mặt của Node 1. Nhờ danh sách các process cần giám sát đã được sao chép sẵn qua CRDT trước đó, Node 2 sẽ tự động khởi động lại các process bị mất trên chính tài nguyên của nó.

---

## 2. Bản Chất Cơ Học Của Broadway & Backpressure Loop

Nếu hệ thống của bạn nhận 50,000 tin nhắn/giây từ Kafka, nhưng database của bạn chỉ có thể xử lý tối đa 5,000 transactions/giây. Nếu bạn dùng một vòng lặp đọc tin nhắn bình thường và spawn process xử lý cho mỗi tin nhắn, bạn sẽ làm sập Database hoặc làm BEAM VM bị cạn kiệt bộ nhớ RAM.

`Broadway` giải quyết việc này bằng một **Vòng Lặp Kéo (Pull-based demand loop)**:

```
+--------------------+
|  Kafka Broker      |
+--------------------+
         ^
         | 1. Gửi request lấy tin nhắn (Demand = 100)
         |
+--------------------+
| Broadway.Producer  | <=== [Broadway.Processor 1] (Rảnh, gửi yêu cầu: Demand = 50)
| (Điều phối demand) | <=== [Broadway.Processor 2] (Rảnh, gửi yêu cầu: Demand = 50)
+--------------------+
         |
         | 2. Nhận 100 tin nhắn, phân phối
         +-----------------------------+
         |                             |
         v                             v
+--------------------+       +--------------------+
| Broadway.Processor1|       | Broadway.Processor2|
| (Xử lý logic nặng) |       | (Xử lý logic nặng) |
+--------------------+       +--------------------+
         |                             |
         +--------------+--------------+
                        | 3. Chuyển tiếp các tin nhắn đã xử lý
                        v
             +--------------------+
             |  Broadway.Batcher  | 
             |  (Gom nhóm tin nhắn|
             |   kích thước = 100)|
             +--------------------+
                        |
                        | 4. Flush hàng loạt (Bulk Insert)
                        v
             +--------------------+
             |  Database / API    |
             +--------------------+
```

*   **Cơ chế hoạt động:**
    1.  Các `Broadway.Processor` (là các process chạy song song) sẽ gửi một tín hiệu nhu cầu (demand) ngược lên cho `Broadway.Producer`. Ví dụ: *"Tôi đang rảnh, hãy cho tôi 50 tin nhắn"*.
    2.  `Broadway.Producer` nhận các yêu cầu này và chỉ pull đúng 100 tin nhắn từ Kafka về để phân phối cho các Processor.
    3.  Nếu Database bị chậm, các Processor sẽ mất nhiều thời gian hơn để xử lý xong công việc hiện tại. Do đó, chúng sẽ chậm gửi tín hiệu demand tiếp theo lên Producer. Producer thấy không có demand từ Processor sẽ dừng việc pull tin nhắn từ Kafka.
    4.  *Kết quả:* Hệ thống tự động giảm tốc độ tiêu thụ tin nhắn (throttling) tương thích chính xác với tốc độ xử lý của hệ thống hạ tầng (Database/Third-party APIs), đảm bảo an toàn tuyệt đối cho hệ thống.

---

## 3. Telemetry Dispatch Pipeline dưới góc nhìn Hệ Điều Hành

Một số lập trình viên nghĩ Telemetry hoạt động bằng cách mở các hàng đợi ngầm hoặc chạy các background threads. Điều này hoàn toàn sai. Telemetry chạy **hoàn toàn đồng bộ (synchronous) trên chính process phát ra sự kiện**.

```elixir
# 1. Định nghĩa Handler
defmodule MetricLogger do
  def log_query_time(_event_name, measurements, _metadata, _config) do
    duration = measurements.query_time
    IO.puts("Query took: #{duration}ms")
  end
end

# 2. Đăng ký Handler (Thực chất là lưu hàm vào một ETS table toàn cục)
:telemetry.attach("my-logger", [:ecto, :repo, :query, :stop], &MetricLogger.log_query_time/4, nil)

# 3. Code phát sự kiện trong Ecto
def execute_query(sql) do
  start_time = System.monotonic_time()
  result = run_raw_sql(sql)
  duration = System.monotonic_time() - start_time
  
  # PHÁT SỰ KIỆN: Bản chất là một vòng lặp qua ETS table để gọi trực tiếp các hàm handler đã đăng ký
  :telemetry.execute([:ecto, :repo, :query, :stop], %{query_time: duration}, %{sql: sql})
  
  result
end
```

*   **Tại sao lại thiết kế như vậy?**
    *   **Không tốn tài nguyên chạy ngầm:** Vì nó chỉ là các lượt gọi hàm trực tiếp (direct function calls), nếu không có handler nào đăng ký cho sự kiện đó, chi phí thực thi gần như bằng 0 (chỉ mất chi phí kiểm tra sự tồn tại trong ETS table).
    *   **Cảnh báo cực kỳ quan trọng cho Senior:** Vì handler chạy đồng bộ trên chính process phát sự kiện, nếu bạn viết code xử lý chậm hoặc gọi chặn (blocking I/O, API call) bên trong hàm handler (`log_query_time`), bạn sẽ làm chậm trực tiếp process đang chạy ứng dụng (ví dụ: làm chậm câu query DB hoặc chậm request của HTTP client).
    *   *Cách xử lý đúng:* Nếu cần xử lý phức tạp trong handler, hãy dùng handler để gửi message bất đồng bộ (`send/2`) tới một worker GenServer riêng để xử lý ngoài luồng.

---

## 4. Kiến Trúc System Design: Notification Gateway (100k CCU)

Khi phỏng vấn Senior, nếu bạn chỉ nói *"Tôi sẽ dùng Elixir vì nó scale tốt"*, bạn sẽ rớt. Bạn phải giải thích được chi tiết kiến trúc hạ tầng và các kịch bản lỗi (Failure Modes).

### 4.1. Sơ đồ kiến trúc tổng thể
```
                          [ Client / Web Browser ]
                                     |
                       (WebSocket / Sticky Session)
                                     v
                       [ Load Balancer (HAProxy) ]
                                     |
                   +-----------------+-----------------+
                   | (Node IP hash)                    | (Node IP hash)
                   v                                   v
        [ App Server Node 1 ]               [ App Server Node 2 ]
        (libcluster / Full Mesh) <=========> (libcluster / Full Mesh)
        - User1 Connected                   - User2 Connected
        - Channel PID 101                   - Channel PID 202
```

### 4.2. Giải quyết bài toán định tuyến tin nhắn (Routing)
*   **Kịch bản:** User 1 đang kết nối WebSocket tới `Node 1` (được quản lý bởi Channel Process có PID `101`). Hệ thống có một tin nhắn mới gửi cho User 1, nhưng event này lại được nhận bởi `Node 2` (từ Kafka consumer chạy trên Node 2). Làm sao Node 2 chuyển được tin nhắn này tới Node 1?
*   **Giải pháp:**
    1.  Mỗi khi User 1 kết nối vào Node 1, Channel process sẽ tự động đăng ký tham gia vào nhóm PubSub của User 1: `Phoenix.PubSub.subscribe(MyApp.PubSub, "user:1")`.
    2.  Khi Node 2 nhận được event gửi cho User 1, nó gọi: `Phoenix.PubSub.broadcast(MyApp.PubSub, "user:1", {:new_msg, data})`.
    3.  `Phoenix.PubSub` sử dụng Erlang `:pg` (Process Groups) phân tán dưới nền tảng để biết rằng có một listener đăng ký topic `"user:1"` nằm ở Node 1. Nó tự động đóng gói message gửi qua liên kết TCP của 2 Node tới Node 1.
    4.  Node 1 nhận được message, chuyển tiếp cho Channel process `PID 101` để push trực tiếp xuống client qua WebSocket.

### 4.3. Quản lý trạng thái kết nối & Node Failover (Khi Node 1 bị sập)
*   **Vấn đề:** Nếu Node 1 đột ngột bị sập (ví dụ: server bị reboot), 50k client đang kết nối tới Node 1 sẽ bị ngắt kết nối đồng loạt.
*   **Giải pháp xử lý thảm họa (Disaster Recovery):**
    1.  **Client-side Retry with Jitter (Thử lại ở phía Client):** Client phải có cơ chế tự động kết nối lại khi mất socket. Tuy nhiên, nếu cả 50k clients cùng lúc kết nối lại tới Node 2 ngay lập tức, chúng sẽ tạo ra hiện tượng **Thundery Herd (Bầy đàn sấm sét)** làm sập luôn Node 2. Client bắt buộc phải sử dụng thuật toán **Exponential Backoff với Jitter** (thời gian chờ tăng dần ngẫu nhiên, ví dụ: thử lại sau $1s \pm 200ms$, rồi $2s \pm 400ms$, v.v.) để dàn đều lượng request kết nối lại.
    2.  **Shared State (Không lưu trạng thái cứng trên Node):** Mọi thông tin giỏ hàng, session dữ liệu không được lưu cứng trong RAM của riêng Node 1. Chúng phải được đồng bộ qua Redis, Database hoặc lưu trong cookies mã hóa của client (JWT/Session token). Khi client kết nối lại sang Node 2, Node 2 hoàn toàn có thể phục hồi lại phiên làm việc mà không làm mất dữ liệu của người dùng.
