# 📔 Ngày 1: Deep Dive BEAM VM, OTP Internals & Database Optimizations

## 1. BEAM VM Internals (Kiến thức nâng cao dành cho Senior)

### Process Scheduling & Reductions
*   **Schedulers:** Khi BEAM khởi động, nó tự động nhận diện số lượng CPU core logic của máy chủ và khởi chạy số lượng Scheduler tương ứng (1 scheduler/core). Mỗi Scheduler chạy trên một OS thread riêng biệt.
*   **Run Queues:** Mỗi scheduler sở hữu một run queue riêng chứa các process sẵn sàng chạy. Để tránh hiện tượng lệch tải (một core bận rộn còn core khác rảnh rỗi), BEAM sử dụng cơ chế **Work Stealing**: một scheduler rảnh rỗi sẽ chủ động lấy bớt process từ run queue của scheduler đang bị quá tải.
*   **Reduction Budget (Preemptive Scheduling):** 
    *   Mỗi thao tác tính toán hoặc hàm gọi trong BEAM được gán một chi phí gọi là **reduction**. Mỗi process khi được lập lịch chạy sẽ được cấp một quota là **2000 reductions**.
    *   Khi process tiêu thụ hết 2000 reductions này, scheduler sẽ lưu trạng thái (context switch) của process đó lại, đẩy nó xuống cuối run queue và nhường quyền cho process khác.
    *   *Ý nghĩa:* Cơ chế preemptive scheduling đảm bảo tính **Soft Real-time** và độ trễ cực thấp (low latency) cho ứng dụng. Không một process tính toán nặng nào (ví dụ: vòng lặp vô hạn) có thể làm treo toàn bộ hệ thống hoặc ảnh hưởng tới việc nhận/gửi request của các process khác.

### Garbage Collection (Generational & Per-process Heap)
*   **Vùng nhớ Heap riêng biệt:** Mỗi process BEAM có Heap và Stack riêng, bắt đầu với kích thước cực kỳ nhỏ (~309 words, khoảng 2.5 KB). Stack lớn dần từ trên xuống, Heap lớn dần từ dưới lên trong cùng một vùng nhớ được cấp phát.
*   **Generational GC:** BEAM áp dụng cơ chế GC theo thế hệ (Generational GC) gồm 2 phân vùng:
    *   **Young Generation (New Heap):** Nơi chứa các dữ liệu mới được tạo ra. GC chạy ở đây rất thường xuyên (Minor GC) bằng thuật toán Copying Collector (chép các dữ liệu còn sống sang vùng nhớ mới và dọn sạch vùng cũ).
    *   **Old Generation (Old Heap):** Khi các dữ liệu sống sót qua một số chu kỳ Minor GC nhất định, chúng được chuyển sang Old Heap. GC ở đây chạy ít thường xuyên hơn (Major GC) vì chi phí dọn dẹp lớn hơn.
*   **Binary Heap (Off-heap storage):** 
    *   Các dữ liệu kiểu binary có kích thước **lớn hơn 64 bytes** (gọi là *Refc Binaries*) không được lưu trữ trực tiếp trên process heap của từng process.
    *   Thay vào đó, chúng được lưu trữ ở một vùng nhớ dùng chung toàn cục (Global Shared Heap). Trực tiếp trên process heap chỉ lưu một con trỏ tham chiếu (size 24 bytes) trỏ tới vùng nhớ dùng chung này kèm theo một bộ đếm tham chiếu (Reference Counter).
    *   *Lưu ý rò rỉ bộ nhớ (Memory Leak):* Nếu một process giữ một tham chiếu nhỏ tới một Binary lớn (ví dụ: parse một file JSON 10MB rồi giữ lại một key nhỏ 10 bytes), cả khối 10MB kia sẽ không thể giải phóng khỏi Global Heap cho đến khi process đó chết hoặc chạy GC thu hồi con trỏ tham chiếu đó.

### Triết lý "Let it crash" & Fault Tolerance
*   Tránh việc bọc mọi dòng code bằng `try/catch` hoặc `begin/rescue` vì nó làm bẩn codebase và khó xác định trạng thái nhất quán của dữ liệu.
*   Nếu có lỗi bất ngờ, hãy để process đó crash tự nhiên. Supervisor sẽ chịu trách nhiệm giám sát và tái tạo lại process đó với trạng thái khởi tạo sạch sẽ, an toàn đã biết trước.

---

## 2. Erlang/OTP Architecture & State Management

### Tránh nghẽn cổ chai (Bottlenecks) trong GenServer
*   **Nguyên nhân:** Bản chất GenServer xử lý các tin nhắn tuần tự (Single-threaded execution model). Nếu hàng ngàn process khác cùng gọi đồng bộ (`handle_call`) tới duy nhất một GenServer trung tâm, nó sẽ tạo ra hàng đợi mailbox khổng lồ và gây nghẽn (bottleneck).
*   **Các giải pháp khắc phục:**
    1.  **Phân mảnh trạng thái (Sharding/Partitioning):** Sử dụng `PartitionSupervisor` để chia nhỏ tải trọng ra nhiều GenServer workers song song dựa trên một hashing key (ví dụ: hash `user_id` để đưa request về đúng phân vùng worker).
    2.  **Đọc/Ghi song song bằng ETS (Erlang Term Storage):** ETS cho phép đọc ghi dữ liệu in-memory trực tiếp từ bất kỳ process nào với tốc độ cực nhanh mà không cần đi qua mailbox của một GenServer. Hãy dùng GenServer làm Owner ghi dữ liệu, còn các process khác đọc trực tiếp từ ETS table.
    3.  **Xử lý bất đồng bộ (Offloading):** Với các tác vụ tốn thời gian (như gửi email, gọi API bên thứ ba), GenServer không được xử lý trực tiếp trong `handle_call`. Thay vào đó, nó nên spawn một `Task` hoặc sử dụng `Task.Supervisor` để làm việc đó độc lập, sau đó trả về kết quả bất đồng bộ.

### Supervision Trees & Strategies
*   **one_for_one:** Thích hợp cho các worker độc lập. Một chết, một sống lại.
*   **one_for_all:** Nếu các child processes phụ thuộc lẫn nhau, thiếu một đứa thì hệ thống không hoạt động được. Ví dụ: Process A đọc socket, Process B ghi log, Process C phân tích cú pháp. Một đứa chết -> tất cả cùng khởi động lại.
*   **rest_for_one:** Các child processes được khởi tạo theo thứ tự tuyến tính phụ thuộc. Nếu process khởi tạo trước crash, các process khởi tạo sau nó sẽ bị kéo đổ theo và cùng restart.
*   **DynamicSupervisor:** Chuyên dùng để khởi chạy động các worker trong runtime. Cần lưu ý sử dụng tùy chọn `restart: :transient` hoặc `:temporary` cho các worker động này để tránh việc supervisor cố gắng restart vô hạn một session đã logout hoặc kết thúc nhiệm vụ bình thường.

---

## 3. Database (Ecto & PostgreSQL) & Web APIs (Phoenix & Absinthe)

### Tối ưu hóa truy vấn Ecto
1.  **Giải quyết N+1 Query triệt để:**
    *   *Cách 1 (Preload):* `Repo.all(from p in Post, preload: [:comments])` - Ecto sẽ chạy 2 câu truy vấn riêng biệt: một câu lấy Posts, một câu lấy tất cả Comments của các Posts đó, rồi tự map lại ở RAM.
    *   *Cách 2 (Inner/Left Join):* `from p in Post, join: c in assoc(p, :comments), preload: [comments: c]` - Ecto chạy duy nhất 1 câu SQL dùng `JOIN` để lấy toàn bộ dữ liệu. Phù hợp khi bạn cần lọc dữ liệu Post dựa trên điều kiện của Comment.
2.  **Ecto.Multi vs DB Transactions:**
    *   Không nên viết code lồng nhau dạng `Repo.transaction(fn -> ... end)` nếu có nhiều logic nghiệp vụ phức tạp vì nó khó debug, khó viết unit test độc lập cho từng phần.
    *   `Ecto.Multi` là một cấu trúc dữ liệu mô tả các bước giao dịch dưới dạng một pipeline. Bạn có thể xây dựng nó một cách linh hoạt, truyền qua các module khác nhau trước khi thực thi thực tế bằng `Repo.transaction(multi)`.
3.  **Khóa dòng (Database Row Locking):**
    *   Sử dụng `lock: "FOR UPDATE"` trong Ecto query khi cập nhật số dư tài khoản hoặc số lượng tồn kho để ngăn chặn hiện tượng **Lost Update** khi 2 transactions chạy song song cùng đọc một giá trị và ghi đè lên nhau.

### Tối ưu hóa GraphQL API với Absinthe
*   **Vấn đề N+1 trong GraphQL:** Mỗi field resolver trong Absinthe chạy độc lập. Nếu user truy vấn danh sách `posts` kèm theo `author` của mỗi post, Absinthe sẽ gọi resolver của `author` N lần.
*   **Giải pháp (Absinthe Dataloader):**
    *   Dataloader là một công cụ giúp gom nhóm (batching) các request truy vấn database.
    *   Thay vì chạy câu query ngay lập tức, Dataloader sẽ tạm dừng thực thi của resolver, gom tất cả các ID cần tìm kiếm, chạy duy nhất một câu query `SELECT ... WHERE id IN (...)` để lấy toàn bộ data, sau đó phân phối lại kết quả cho các resolver.

---

## 🚀 Câu hỏi phỏng vấn thử thách Ngày 1

1.  *Làm thế nào để truyền một lượng lớn dữ liệu (> 1GB) giữa hai process Elixir trên cùng một node mà không làm tràn bộ nhớ heap?*
    *   **Trả lời:** Sử dụng các Binary lớn hơn 64 bytes. Do chúng được lưu trữ ở Off-heap (Binary Heap toàn cục), việc truyền message chứa binary này giữa các process chỉ là việc copy một con trỏ tham chiếu (24 bytes) và tăng Reference Counter, hoàn toàn không copy dữ liệu thực tế giúp tốc độ truyền tải cực nhanh và tiết kiệm bộ nhớ.
2.  *Khi nào bạn nên dùng `DynamicSupervisor` kết hợp với `Registry` và làm sao để xử lý race condition khi 2 request đồng thời yêu cầu khởi tạo worker cho cùng một ID?*
    *   **Trả lời:** Ta dùng DynamicSupervisor + Registry để quản lý các thực thể động như Session chat, User shopping cart. Để tránh race condition khi khởi tạo trùng, ta cấu hình Registry ở dạng `:unique`. Khi gọi `DynamicSupervisor.start_child`, Registry sẽ chặn việc đăng ký trùng tên và trả về lỗi `{:error, {:already_started, pid}}`. Chúng ta sẽ match lỗi này và lấy trực tiếp `pid` của process đang chạy thay vì khởi tạo mới.
