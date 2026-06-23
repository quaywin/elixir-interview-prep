# 🎯 Lộ trình Ôn tập 2 Ngày - Senior Elixir Interview (10pearls)

Thư mục này chứa toàn bộ tài liệu lý thuyết, câu hỏi phỏng vấn thực tế và bài tập coding giúp bạn chuẩn bị nhanh nhất trong **2 ngày** cho buổi phỏng vấn tại 10pearls.

---

## 📅 Lịch Trình Chi Tiết

### **Ngày 1: Core OTP, Database (Ecto/Postgres) & Coding**
*   **Lý thuyết (Sáng):** Xem chi tiết tại [day1_prep.md](day1_prep.md). Tập trung vào BEAM Internals, GenServer callbacks, Supervision Trees và Ecto optimizations.
*   **Thực hành (Chiều):** Bài tập Ledger với `Ecto.Multi` và Unit Test.
    *   File thực hành: [ledger_practice.exs](ledger_practice.exs)
*   **Luyện tập (Tối):** Tự trả lời các câu hỏi phản xạ nhanh trong tài liệu Ngày 1.

### **Ngày 2: Distributed Systems, System Design, DevOps & Behavioral**
*   **Lý thuyết & Kiến trúc (Sáng):** Xem chi tiết tại [day2_prep.md](day2_prep.md). Tập trung vào Clustering, Message Brokers (Kafka vs RabbitMQ), Observability (:telemetry, Prometheus) và DevOps.
*   **Thực hành (Chiều):** Bài tập GenServer Rate Limiter & Task supervision.
    *   File thực hành: [rate_limiter_practice.exs](rate_limiter_practice.exs)
*   **System Design & Mock (Tối):** Thiết kế Notification Gateway (100k CCU) và chuẩn bị các câu chuyện STAR.

---

## 💻 Hướng Dẫn Chạy Bài Tập Thực Hành (Live Coding)

Các bài tập thực hành được thiết kế dưới dạng file script Elixir độc lập (`.exs`), đã tích hợp sẵn framework test `ExUnit`. Bạn có thể chạy trực tiếp bằng terminal mà không cần khởi tạo dự án Mix mới.

1.  **Bài tập Ngày 1 (Ledger Transaction):**
    ```bash
    elixir ledger_practice.exs
    ```
2.  **Bài tập Ngày 2 (Rate Limiter):**
    ```bash
    elixir rate_limiter_practice.exs
    ```

*Mỗi file đều chứa sẵn mô tả yêu cầu, code khung (skeleton code) kèm các TODO cần hoàn thành, và bộ test suite để bạn tự đánh giá độ chính xác của giải pháp.*

---

## 💡 Lời khuyên quan trọng khi phỏng vấn Senior tại 10pearls
*   **Think Out Loud:** Khi live coding, hãy liên tục giải thích tư duy của bạn (ví dụ: tại sao dùng pattern matching thay vì if/else, tại sao dùng `Ecto.Multi` thay vì transaction block thông thường).
