# 📔 Ngày 2: Distributed Systems, Message Brokers, DevOps & System Design (Nâng cao)

## 1. Distributed Systems & Clustering (Kiến thức Hệ thống phân tán)

### Kết nối cụm Node & Node Discovery
*   **Erlang Cookie:** Để hai hoặc nhiều node BEAM có thể kết nối với nhau, chúng phải có chung một chuỗi bảo mật gọi là Erlang Cookie (thường lưu ở file `~/.erlang.cookie` hoặc được cấu hình lúc runtime).
*   **libcluster:** Trong môi trường Kubernetes, `libcluster` hỗ trợ các chiến lược (strategies) tự động phát hiện node:
    *   `Cluster.Strategy.DNSPoll`: Lấy danh sách IPs của các pods thông qua một Headless Service DNS trong K8s.
    *   `Cluster.Strategy.Kubernetes`: Truy vấn trực tiếp API server của Kubernetes để lấy danh sách pod IPs có chung nhãn (labels).

### Phân tán State toàn Cluster (Distributed State)
*   **Horde (Distributed Supervisor & Registry):**
    *   Trong hệ thống phân tán, nếu một node bị chết (network partition hoặc crash hardware), toàn bộ các process chạy trên node đó sẽ mất.
    *   `Horde.DynamicSupervisor` sử dụng thuật toán **CRDT (Conflict-Free Replicated Data Type)** để đồng bộ hóa danh sách các process cần giám sát trên toàn cụm. Khi phát hiện một node chết, các node còn lại sẽ tự động khởi chạy lại (takeover) các process bị mất trên node của chúng.
    *   `Horde.Registry` giúp tìm kiếm PID của một process nằm ở bất kỳ node nào trong cluster một cách phi tập trung, không bị điểm nghẽn đơn lẻ (single point of failure).
*   **Mạng lưới PubSub (Phoenix.PubSub):**
    *   Hoạt động dựa trên module Erlang `:pg` (Process Groups) hoặc adapter Redis.
    *   Khi node A gọi `Phoenix.PubSub.broadcast(PubSub, "room:1", message)`, PubSub sẽ tự động gửi message này qua mạng tới tất cả các node khác trong cluster để phân phối tới các client kết nối trực tiếp vào node của họ.

---

## 2. Message Brokers & Event-Driven Architecture

### Xử lý Message bất đồng bộ & Backpressure với Broadway
*   **Backpressure (Áp lực ngược):** Là cơ chế ngăn chặn consumer bị tràn bộ nhớ khi producer gửi tin nhắn với tốc độ quá nhanh.
*   ** Broadway Pipeline:**
    ```
    Producer (SQS/Kafka) -> [Broadway.Producer] -> [Broadway.Processor] -> [Broadway.Batcher] -> Consumer/DB
    ```
    1.  `Broadway.Producer` kiểm tra số lượng message tối đa mà hệ thống có thể xử lý tại một thời điểm (`max_demand`). Nó chỉ pull thêm message từ broker khi hệ thống có tài nguyên rảnh rỗi.
    2.  `Broadway.Processor` thực hiện các tác vụ tính toán song song độc lập trên từng message (ví dụ: parse JSON, transform data).
    3.  `Broadway.Batcher` gom nhóm các message đã xử lý thành từng lô (batch) dựa trên kích thước (`batch_size`) hoặc thời gian chờ (`batch_timeout`) trước khi thực hiện ghi hàng loạt xuống Database (Batch insert) nhằm tối ưu IOPS.
*   **Dead Letter Queue (DLQ):** Khi một message bị lỗi quá số lần cấu hình (retry limit), Broadway sẽ không gửi lại (nack) nữa mà đẩy nó sang một hàng đợi lỗi riêng (DLQ) để kỹ sư có thể phân tích thủ công sau, tránh làm nghẽn hàng đợi chính.

---

## 3. Observability & DevOps

### Cấu trúc Telemetry Pipeline
*   **Telemetry** là một thư viện dựa trên sự kiện (event-based). Nó không chạy background process hay ghi đè hàm, nên chi phí thực thi cực kỳ thấp.
*   **Luồng hoạt động:**
    1.  *Gắn sự kiện:* Thư viện Ecto phát ra sự kiện: `:telemetry.execute([:ecto, :repo, :query, :stop], measurements, metadata)`.
    2.  *Lắng nghe:* Trong file khởi chạy ứng dụng, ta đăng ký hàm handler:
        ```elixir
        :telemetry.attach("ecto-queries", [:ecto, :repo, :query, :stop], &MyHandler.handle_event/4, nil)
        ```
    3.  *Xử lý:* Hàm `handle_event/4` nhận các thông số đo lường (như thời gian thực thi query) và xuất ra Prometheus Counter/Histogram hoặc ghi log.

### Quy trình CI/CD & Multi-stage Dockerfile cho Elixir
*   **Mix Release:** Build code Elixir ra mã máy BEAM bytecode (`.beam`), đóng gói toàn bộ thư viện Erlang/Elixir phụ thuộc và runtime engine (ERTS). Image chạy cuối cùng hoàn toàn độc lập với source code gốc và compiler.
*   **Multi-Stage Dockerfile chuẩn Senior:**
    ```dockerfile
    # Stage 1: Build environment
    FROM elixir:1.15-alpine AS builder
    RUN apk add --no-cache build-base git
    WORKDIR /app
    RUN mix local.hex --force && mix local.rebar --force
    ENV MIX_ENV=prod
    COPY mix.exs mix.lock ./
    RUN mix deps.get --only prod
    RUN mix deps.compile
    COPY . .
    RUN mix release

    # Stage 2: Minimal Runtime Environment
    FROM alpine:3.18
    RUN apk add --no-cache openssl ncurses-libs libstdc++
    WORKDIR /app
    COPY --from=builder /app/_build/prod/rel/my_app ./
    ENV MIX_ENV=prod
    CMD ["/app/bin/my_app", "start"]
    ```
    *   *Tại sao cần alpine packages:* BEAM VM sau khi release vẫn cần liên kết động với các thư viện hệ thống như `openssl` (để mã hóa SSL), `ncurses` (cho console output).

---

## 4. System Design & Behavioral (Mock Scenarios)

### Thiết kế hệ thống: Real-time Notification Gateway (100k CCU)
*   **Yêu cầu:** Gửi tin nhắn real-time từ hệ thống tới 100k client kết nối đồng thời qua WebSockets.
*   **Thiết kế chi tiết:**
    1.  **Load Balancer (Nginx/HAProxy):** Hỗ trợ WebSocket upgrade, sử dụng thuật toán round-robin hoặc IP hashing.
    2.  **App Servers (Elixir Nodes):** Chạy cụm Elixir liên kết qua `libcluster`. Mỗi user kết nối sẽ mở ra một Phoenix Channel process (dung lượng RAM cực nhỏ ~2KB/connection, 100k CCU chỉ tốn khoảng 200MB RAM).
    3.  **PubSub Layer:** Dùng `Phoenix.PubSub` với adapter phân tán mặc định. Khi có thông báo mới cho User X, ta chỉ cần gọi `PubSub.broadcast("user:X", event)`. Dù User X đang kết nối tới Node 1 hay Node 3, thông báo vẫn được gửi tới chính xác thiết bị của họ.
    4.  **ETS Cache:** Lưu trạng thái online/offline của người dùng trực tiếp trên RAM của từng node để truy vấn nhanh mà không cần gọi DB liên tục.

### Câu chuyện STAR mẫu: Troubleshooting Memory Leak trên Production
*   **S (Situation):** Sau khi deploy phiên bản mới, lượng RAM tiêu thụ trên App server tăng dần theo hình răng cưa (memory leak) và crash server (Out Of Memory) sau mỗi 24 giờ.
*   **T (Task):** Nhiệm vụ của tôi là phải tìm ra nguyên nhân rò rỉ bộ nhớ này mà không được làm gián đoạn hệ thống.
*   **A (Action):** 
    1.  Tôi thiết lập một SSH tunnel bảo mật tới node production đang chạy và mở công cụ `:observer.start()` (hoặc sử dụng `Phoenix LiveDashboard` phần OS Mon).
    2.  Tôi nhận thấy số lượng process tăng đột biến và vùng nhớ chiếm dụng chủ yếu nằm ở **Binary Heap** (Global Shared Heap).
    3.  Tôi dùng hàm `:erlang.process_info(pid, :current_stacktrace)` trên các process có dung lượng lớn nhất và phát hiện team đã parse các file XML lớn từ đối tác bằng thư viện không tối ưu, giữ lại các đoạn substring nhỏ trong state của GenServer lâu dài khiến GC không thể thu hồi toàn bộ file XML thô 50MB.
    4.  Tôi refactor code bằng cách sử dụng `:binary.copy/1` để ép BEAM giải phóng vùng nhớ file XML lớn và chỉ giữ lại chuỗi con thực sự cần thiết trong RAM.
*   **R (Result):** Lượng RAM tiêu thụ ngay lập tức giảm từ 4GB về mức ổn định 300MB. Hệ thống hoạt động trơn tru không còn tình trạng crash OOM.
