# 🎯 Lộ trình Ôn tập 2 Ngày - Senior Elixir Interview (10pearls)

Thư mục này chứa toàn bộ tài liệu lý thuyết, câu hỏi phỏng vấn thực tế và bài tập coding giúp bạn chuẩn bị nhanh nhất trong **2 ngày** cho buổi phỏng vấn tại 10pearls.

---

## 📅 Lịch Trình Chi Tiết

### **Ngày 1: Core OTP, Database (Ecto/Postgres) & Coding**
*   **Lý thuyết (Sáng):** Xem chi tiết tại [day1_prep.md](day1_prep.md). Tập trung vào BEAM Internals, GenServer callbacks, Supervision Trees và Ecto optimizations.
*   **Thực hành (Chiều):** Có 2 bài tập thực hành từ cơ bản đến nâng cao:
    1.  **Ledger Transaction:** Giao dịch ngân hàng an toàn sử dụng `Ecto.Multi` và Sandbox isolation.
        *   File: [ledger_practice.exs](ledger_practice.exs)
    2.  **Session Manager:** Quản lý process động sử dụng `DynamicSupervisor` và `Registry` định danh.
        *   File: [session_manager_practice.exs](session_manager_practice.exs)
*   **Luyện tập (Tối):** Tự trả lời các câu hỏi phản xạ nhanh trong tài liệu Ngày 1.

### **Ngày 2: Distributed Systems, System Design, DevOps & Behavioral**
*   **Lý thuyết & Kiến trúc (Sáng):** Xem chi tiết tại [day2_prep.md](day2_prep.md). Tập trung vào Clustering, Message Brokers (Kafka vs RabbitMQ), Observability (:telemetry, Prometheus) và DevOps.
*   **Thực hành (Chiều):** Có 2 bài tập thực hành về Concurrency & Rate limiting:
    1.  **Rate Limiter:** GenServer quản lý tần suất request trên mỗi IP có reset timer.
        *   File: [rate_limiter_practice.exs](rate_limiter_practice.exs)
    2.  **Batch Processor:** gom nhóm dữ liệu theo lô (batching) tự động flush dựa trên kích thước hoặc timeout.
        *   File: [batcher_practice.exs](batcher_practice.exs)
*   **System Design & Mock (Tối):** Thiết kế Notification Gateway (100k CCU) và chuẩn bị các câu chuyện STAR.

---

## 💻 Hướng Dẫn Chạy Bài Tập Thực Hành (Live Coding)

Các bài tập thực hành được thiết kế dưới dạng file script Elixir độc lập (`.exs`), đã tích hợp sẵn framework test `ExUnit`. Bạn có thể chạy trực tiếp bằng terminal mà không cần khởi tạo dự án Mix mới.

1.  **Chạy bài tập Ngày 1:**
    ```bash
    elixir ledger_practice.exs
    elixir session_manager_practice.exs
    ```
2.  **Chạy bài tập Ngày 2:**
    ```bash
    elixir rate_limiter_practice.exs
    elixir batcher_practice.exs
    ```

*Mỗi file đều chứa sẵn mô tả yêu cầu, code khung (skeleton code) kèm các TODO cần hoàn thành, và bộ test suite để bạn tự đánh giá độ chính xác của giải pháp. Lời giải gợi ý có sẵn ở cuối mỗi file.*

---

## 💡 Lời khuyên quan trọng khi phỏng vấn Senior tại 10pearls
*   **Think Out Loud:** Khi live coding, hãy liên tục giải thích tư duy của bạn (ví dụ: tại sao dùng pattern matching thay vì if/else, tại sao dùng `Ecto.Multi` thay vì transaction block thông thường).
*   **Trade-off Mindset:** Khi thiết kế hệ thống, luôn nêu rõ ưu và nhược điểm của từng công nghệ (ví dụ: Redis vs ETS, Kafka vs RabbitMQ). Không có giải pháp hoàn hảo, chỉ có giải pháp phù hợp nhất với bối cảnh.
*   **STAR structure:** Khi trả lời các câu hỏi tình huống (behavioral), hãy đi thẳng vào bối cảnh (Situation), nhiệm vụ (Task), hành động cụ thể của bạn (Action) và kết quả đo lường được (Result).
