# 📔 Ngày 2: Distributed Systems, Message Brokers, DevOps & System Design

## 1. Distributed Systems & Clustering

### Cách kết nối các Node (Elixir Cluster)
*   **Cơ chế:** BEAM VM hỗ trợ kết nối phân tán qua giao thức Erlang Distribution. Khi khởi chạy node với tên gọi (`iex --sname node1` hoặc `--name node1@ip`), các node có thể kết nối với nhau qua `Node.connect/1`.
*   **Tự động phát hiện (Auto-discovery):** Trong thực tế cloud/Kubernetes, chúng ta sử dụng thư viện `libcluster`. Nó hỗ trợ tìm kiếm các node cùng cluster qua DNS, Kubernetes API, Consul, EC2 tags, v.v. và tự kết nối chúng lại với nhau.

### Phân tán State và Global Process
*   **pg (Process Groups):** Module tích hợp sẵn của Erlang giúp quản lý các nhóm process phân tán trên nhiều node khác nhau. Rất hữu ích cho các bài toán PubSub hoặc Group chat.
*   **Registry vs Distributed Registry:** `Registry` chỉ hoạt động cục bộ (local) trên một node duy nhất. Nếu cần định danh process toàn cluster, cần sử dụng các giải pháp như `:global` (phân tán có khóa - locking), `Horde` (Dynamic Supervisor & Registry phân tán hỗ trợ tự phục hồi khi node chết).

---

## 2. Message Brokers & Event-Driven Architecture

### Phân biệt Kafka, RabbitMQ & NATS
*   **Apache Kafka:**
    *   *Mô hình:* Log-based PubSub, Append-only commit log.
    *   *Đặc điểm:* Lưu giữ tin nhắn (retention) lâu dài, consumer tự quản lý vị trí đọc (offset). Hỗ trợ throughput cực kỳ cao.
    *   *Phù hợp cho:* Event Sourcing, Data Analytics stream, Log aggregation, Audit Trails.
*   **RabbitMQ:**
    *   *Mô hình:* Message Queuing (Smart Broker / Dumb Consumer).
    *   *Đặc điểm:* Hỗ trợ định tuyến phức tạp (Routing keys, Exchange types), tin nhắn biến mất khỏi queue ngay sau khi consumer xử lý và ACK.
    *   *Phù hợp cho:* Task queues, Asynchronous job processing, Work distribution.
*   **NATS / NATS JetStream:**
    *   *Mô hình:* Lightweight Messaging System, siêu nhanh, độ trễ cực thấp.
    *   *Phù hợp cho:* Microservice communication, IoT, Real-time status updates.

### Sử dụng Broadway & GenStage trong Elixir
*   **GenStage:** Cung cấp cơ chế **Backpressure** cho hệ thống sản xuất/tiêu thụ dữ liệu trong Elixir. Ngăn chặn việc consumer bị quá tải do producer gửi tin nhắn quá nhanh.
*   **Broadway:** Xây dựng trên GenStage, chuyên dùng để xử lý dữ liệu từ Message Brokers (Kafka, SQS, RabbitMQ). Tích hợp sẵn:
    *   Định cấu hình số lượng workers chạy song song (Concurrency control).
    *   Tự động gom nhóm tin nhắn (Batching) để ghi xuống DB nhanh hơn.
    *   Xử lý lỗi tự động, cơ chế ACK/NACK và Dead Letter Queues (DLQ).

---

## 3. Observability & DevOps

### Telemetry & Metrics
*   **Telemetry:** Thư viện chuẩn trong hệ sinh thái Elixir. Nó hoạt động dựa trên cơ chế Dispatch/Listen sự kiện. Bất kỳ thư viện nào (Phoenix, Ecto, Broadway) đều phát ra các telemetry events dạng: `[:ecto, :repo, :query, :stop]`.
*   **Prometheus & Grafana:** Chúng ta viết code lắng nghe telemetry events này, chuyển đổi thành metric dạng Counters/Gauges/Histograms để Prometheus pull về, sau đó dùng Grafana để vẽ đồ thị giám sát.

### Releases & Containerization
*   **Mix Releases:** Từ Elixir 1.9, ta dùng `mix release` để build ứng dụng thành một package chạy độc lập. Package này **không cần** cài đặt sẵn Elixir hay Erlang trên máy server, vì nó đã đóng gói sẵn BEAM VM thu gọn (ERTS) và code đã biên dịch.
*   **Multi-stage Dockerfile:** Giúp giảm dung lượng Docker image.
    1.  *Stage 1 (Build):* Chứa đầy đủ OS toolchain, Elixir, Erlang, Mix để compile code và build release.
    2.  *Stage 2 (Runtime):* Sử dụng một OS base cực nhỏ (ví dụ: `alpine` hoặc `debian:slim`), chỉ copy folder release từ Stage 1 sang. Giúp image từ ~1GB giảm xuống còn ~50MB và tăng tính bảo mật cho server.

---

## 4. Behavioral Questions (STAR Method)
Hãy chuẩn bị trước tối thiểu 3 câu chuyện thực tế của bản thân theo khung STAR (**S**ituation - **T**ask - **A**ction - **R**esult).

### Kịch bản 1: Giải quyết sự cố production (Troubleshooting)
*   **S:** Hệ thống bị đứng/chậm/crash đột ngột (ví dụ: memory leak hoặc nghẽn DB connection).
*   **T:** Nhiệm vụ của bạn là phải tìm ra nguyên nhân gốc rễ và khôi phục hệ thống trong thời gian ngắn nhất.
*   **A:** Hành động cụ thể: Dùng `:observer` trên production (hoặc qua SSH tunnel), đọc metrics Telemetry để phát hiện CPU/Memory spike, sử dụng Ecto explain analyze để tìm slow query, v.v.
*   **R:** Kết quả: Thời gian khôi phục hệ thống, hiệu suất cải thiện bao nhiêu %, bài học rút ra để phòng ngừa.

### Kịch bản 2: Mentor / Dẫn dắt Technical (Leadership)
*   **S:** Team có nhiều kỹ sư mới chưa quen thuộc với lập trình hàm (Functional Programming) và OTP.
*   **T:** Bạn phải giúp họ làm quen với codebase và code đúng tiêu chuẩn của Elixir/OTP.
*   **A:** Hành động: Tổ chức code reviews chất lượng, giải thích sự khác biệt giữa stateful OOP và stateless FP, pair programming hướng dẫn thiết kế Supervision trees.
*   **R:** Đội ngũ nâng cao năng suất, giảm thiểu số lượng bug trên production, cải thiện code quality.

---

## 🚀 Thử thách thực hành Ngày 2
Hãy mở file [rate_limiter_practice.exs](rate_limiter_practice.exs) và hoàn thành bài tập thiết kế **GenServer Rate Limiter** xử lý concurrency và backpressure.
