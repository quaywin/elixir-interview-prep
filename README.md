# 🎯 Lộ trình Ôn tập 2 Ngày - Senior Elixir Interview (10pearls)

Thư mục này chứa toàn bộ tài liệu lý thuyết, câu hỏi phỏng vấn thực tế và bài tập coding giúp bạn chuẩn bị nhanh nhất trong **2 ngày** cho buổi phỏng vấn tại 10pearls.

---

## 📅 Lịch Trình Chi Tiết

### **Ngày 1: Core OTP, Database (Ecto/Postgres) & Coding**
*   **Lý thuyết (Sáng):** Xem chi tiết tại [day1_prep.md](day1_prep.md). Tập trung vào BEAM VM scheduling & memory internals, GenServer đệ quy đuôi mailbox mechanics, và Ecto optimizations.
*   **Thực hành (Chiều):** Có 4 bài tập thực hành được phân tách thành các thư mục riêng biệt:
    1.  **Ledger Transaction (Giao dịch sổ cái):** Giao dịch an toàn sử dụng `Ecto.Multi` và Sandbox isolation.
        *   Thư mục: [exercises/01_ledger](exercises/01_ledger)
        *   Mã nguồn: [ledger_practice.exs](exercises/01_ledger/ledger_practice.exs)
        *   Tài liệu giải thích: [ledger_explain.md](exercises/01_ledger/ledger_explain.md)
    2.  **Session Manager (Quản lý phiên):** Quản lý process động sử dụng `DynamicSupervisor` và `Registry` định danh.
        *   Thư mục: [exercises/02_session_manager](exercises/02_session_manager)
        *   Mã nguồn: [session_manager_practice.exs](exercises/02_session_manager/session_manager_practice.exs)
        *   Tài liệu giải thích: [session_manager_explain.md](exercises/02_session_manager/session_manager_explain.md)
    3.  **Job Queue (Hàng đợi công việc - Nâng cao):** Điều phối các Task chạy bất đồng bộ với giới hạn song song (`max_concurrency`) thông qua `Task.Supervisor` và giám sát (`monitor`).
        *   Thư mục: [exercises/03_job_queue](exercises/03_job_queue)
        *   Mã nguồn: [job_queue_practice.exs](exercises/03_job_queue/job_queue_practice.exs)
        *   Tài liệu giải thích: [job_queue_explain.md](exercises/03_job_queue/job_queue_explain.md)
    4.  **Write-Through Cache (Ghi trực tiếp - Nâng cao):** Thiết kế cache với tốc độ đọc cực nhanh song song bằng cách đọc trực tiếp từ bảng ETS, đồng thời đảm bảo an toàn ghi đồng bộ qua GenServer và DB.
        *   Thư mục: [exercises/04_write_through_cache](exercises/04_write_through_cache)
        *   Mã nguồn: [write_through_cache_practice.exs](exercises/04_write_through_cache/write_through_cache_practice.exs)
        *   Tài liệu giải thích: [write_through_cache_explain.md](exercises/04_write_through_cache/write_through_cache_explain.md)
*   **Luyện tập (Tối):** Tự trả lời các câu hỏi phản xạ nhanh trong tài liệu Ngày 1.

### **Ngày 2: Distributed Systems, Message Brokers, DevOps & System Design**
*   **Lý thuyết & Kiến trúc (Sáng):** Xem chi tiết tại [day2_prep.md](day2_prep.md). Tập trung vào Clustering, Message Brokers (Kafka vs RabbitMQ), Observability (:telemetry, Prometheus) và DevOps.
*   **Thực hành (Chiều):** Có 2 bài tập thực hành về Concurrency & Rate limiting:
    1.  **Rate Limiter:** GenServer quản lý tần suất request trên mỗi IP có reset timer.
        *   Thư mục: [exercises/05_rate_limiter](exercises/05_rate_limiter)
        *   Mã nguồn: [rate_limiter_practice.exs](exercises/05_rate_limiter/rate_limiter_practice.exs)
        *   Tài liệu giải thích: [rate_limiter_explain.md](exercises/05_rate_limiter/rate_limiter_explain.md)
    2.  **Batch Processor:** gom nhóm dữ liệu theo lô (batching) tự động flush dựa trên kích thước hoặc timeout.
        *   Thư mục: [exercises/06_batch_processor](exercises/06_batch_processor)
        *   Mã nguồn: [batcher_practice.exs](exercises/06_batch_processor/batcher_practice.exs)
        *   Tài liệu giải thích: [batcher_explain.md](exercises/06_batch_processor/batcher_explain.md)
*   **System Design & Mock (Tối):** Thiết kế Notification Gateway (100k CCU) và chuẩn bị các câu chuyện STAR.

---

## 💻 Hướng Dẫn Chạy Bài Tập Thực Hành (Live Coding)

Các bài tập thực hành được thiết kế dưới dạng file script Elixir độc lập (`.exs`), đã tích hợp sẵn framework test `ExUnit`. Bạn có thể chạy trực tiếp bằng terminal mà không cần khởi tạo dự án Mix mới.

Ví dụ:
```bash
# Ngày 1
elixir exercises/01_ledger/ledger_practice.exs
elixir exercises/02_session_manager/session_manager_practice.exs
elixir exercises/03_job_queue/job_queue_practice.exs
elixir exercises/04_write_through_cache/write_through_cache_practice.exs

# Ngày 2
elixir exercises/05_rate_limiter/rate_limiter_practice.exs
elixir exercises/06_batch_processor/batcher_practice.exs
```

*Mỗi thư mục đều chứa sẵn mã nguồn code mẫu đầy đủ và tài liệu giải thích chi tiết bản chất cơ chế của bài tập đó.*

---

## 💡 Lời khuyên quan trọng khi phỏng vấn Senior tại 10pearls
*   **Think Out Loud:** Khi live coding, hãy liên tục giải thích tư duy của bạn (ví dụ: tại sao dùng pattern matching thay vì if/else, tại sao dùng `Ecto.Multi` thay vì transaction block thông thường).
*   **Trade-off Mindset:** Khi thiết kế hệ thống, luôn nêu rõ ưu và nhược điểm của từng công nghệ (ví dụ: Redis vs ETS, Kafka vs RabbitMQ). Không có giải pháp hoàn hảo, chỉ có giải pháp phù hợp nhất với bối cảnh.
*   **STAR structure:** Khi trả lời các câu hỏi tình huống (behavioral), hãy đi thẳng vào bối cảnh (Situation), nhiệm vụ (Task), hành động cụ thể của bạn (Action) và kết quả đo lường được (Result).
