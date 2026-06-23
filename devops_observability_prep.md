# 🛠️ Cẩm Nang Luyện Tập: DevOps & Giám Sát Hệ Thống (DevOps & Observability Cookbook)

Một Senior Elixir Engineer tại 10pearls không chỉ viết code tốt ở môi trường local mà phải hiểu rõ cách đóng gói (containerization), triển khai (deployment) và giám sát (monitoring) ứng dụng trên production.

Tài liệu này tổng hợp các kiến thức thực chiến về DevOps và Giám sát hệ thống.

---

## 1. Bản Chất Đóng Gói (Multi-stage Dockerfile cho Elixir)

Khi phỏng vấn, nếu bạn đưa ra một Dockerfile thô sơ cài đặt toàn bộ Elixir/Erlang trên production runtime image, bạn sẽ bị đánh giá thấp vì:
*   Kích thước image quá lớn (hơn 1GB) gây tốn băng thông kéo image và bộ nhớ ổ cứng của Kubernetes nodes.
*   Chứa nhiều tool compile (gcc, git, mix) tạo ra nhiều lỗ hổng bảo mật nếu hacker xâm nhập được vào container.

### 1.1. Dockerfile Đạt Chuẩn Senior
```dockerfile
# ==============================================================================
# STAGE 1: Môi trường Build (Compiler & Tools)
# ==============================================================================
FROM elixir:1.15-alpine AS builder

# 1. Cài đặt các công cụ build hệ thống cần thiết cho các thư viện Erlang native (NIFs)
RUN apk add --no-cache build-base git

WORKDIR /app

# 2. Cài đặt Mix & Rebar toàn cục
RUN mix local.hex --force && mix local.rebar --force

# 3. Cấu hình biến môi trường production
ENV MIX_ENV=prod

# 4. Copy mix files và cache dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# 5. Copy mã nguồn và tiến hành compile + build release
COPY . .
RUN mix compile
RUN mix release

# ==============================================================================
# STAGE 2: Môi trường chạy thực tế (Runtime - Tối giản & Bảo mật)
# ==============================================================================
FROM alpine:3.18

# 6. Cài đặt các runtime dependencies tối thiểu (openssl, libstdc++, ncurses-libs)
# BEAM VM được biên dịch động yêu cầu các thư viện hệ thống này để chạy.
RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app

# 7. Chỉ copy folder release đã build từ Stage 1 sang Stage 2
# Bypass hoàn toàn Source code gốc, compiler và Git.
COPY --from=builder /app/_build/prod/rel/my_app ./

# Cấu hình user không có quyền root (non-root user) để tăng tính bảo mật
RUN adduser -D appuser && chown -R appuser:appuser /app
USER appuser

ENV MIX_ENV=prod

# Khởi chạy ứng dụng bằng script release của Mix
CMD ["/app/bin/my_app", "start"]
```

*   **Tại sao release Elixir lại không cần cài Erlang/Elixir ở Stage 2?**
    *   Hàm `mix release` tự động đóng gói toàn bộ code đã compile thành `.beam` files, kèm theo ERTS (Erlang Run-Time System - chứa engine BEAM VM). Image ở Stage 2 chỉ là một OS Alpine siêu nhỏ chứa các file binary này, dung lượng image giảm xuống chỉ còn khoảng **50MB - 80MB**.

---

## 2. Giám Sát Hệ Thống (Observability Pipeline)

Trên production, bạn không thể SSH vào server để gõ `iex --sname production` hoặc mở `:observer` vì lý do bảo mật và phân tán mạng. Bạn phải thu thập dữ liệu về một hệ thống quản lý tập trung.

```
+-----------------------------------------------------------------+
| App Server (Elixir Node)                                        |
|                                                                 |
| [Ecto / Phoenix / Broadway]                                     |
|           | (Phát sự kiện telemetry)                            |
|           v                                                     |
| [ :telemetry event pipeline ]                                   |
|           | (Telemetry.Metrics lắng nghe & chuyển đổi)          |
|           v                                                     |
| [ Telemetry.Metrics.Prometheus adapter ]                        |
|           | (Expose endpoint: /metrics)                         |
+-----------------------------------------------------------------+
                               |
                               | 1. Pull metrics (định kỳ mỗi 15s)
                               v
               +-------------------------------+
               | Prometheus Server (Time-series|
               +-------------------------------+
                               |
                               | 2. Vẽ đồ thị giám sát
                               v
               +-------------------------------+
               | Grafana Dashboard             |
               +-------------------------------+
```

### 2.1. Các chỉ số đo lường (Metrics) quan trọng nhất của BEAM VM
Khi xây dựng Grafana Dashboard cho hệ thống Elixir, bạn phải hiển thị và cài đặt cảnh báo (alert) cho các chỉ số sau:
1.  **Process Count:** Số lượng process đang hoạt động. Nếu số lượng process tăng vọt theo hình thẳng đứng, hệ thống đang bị rò rỉ process (process leak - ví dụ: spawn Task không kiểm soát hoặc GenServer crash lặp lại liên tục).
2.  **Atom Count:** Số lượng Atom hiện tại. BEAM VM không thu hồi bộ nhớ của Atom (Atom không bị garbage collected). Nếu Atom count chạm tới giới hạn mặc định (1,048,576), BEAM VM sẽ **lập tức crash toàn bộ ứng dụng**. 
    *   *Quy tắc an toàn:* Tuyệt đối không dùng `String.to_atom/1` cho dữ liệu nhập vào từ client (như JSON keys, API parameters), chỉ dùng `String.to_existing_atom/1`.
3.  **Run Queue Length:** Số lượng process đang xếp hàng chờ CPU. Nếu con số này lớn hơn số CPU cores của hệ thống trong thời gian dài, ứng dụng đang bị nghẽn năng lực tính toán (CPU bound).
4.  **Ecto Connection Pool:** Số lượng kết nối database đang sử dụng. Nếu chạm ngưỡng tối đa (pool_size), các request HTTP tiếp theo sẽ bị timeout khi chờ kết nối DB.

---

## 💡 Hướng Dẫn Luyện Tập DevOps & Observability
1.  **Viết thử Dockerfile:** Hãy tự tay viết một Multi-stage Dockerfile cho một ứng dụng Elixir trống và build thử trên máy cá nhân để tối ưu hóa kích thước image.
2.  **Đọc cấu hình Telemetry:** Tìm hiểu thư viện `:telemetry` trong Elixir. Xem cách khai báo các metric dạng `counter`, `sum`, `last_value` trong file `lib/my_app_web/telemetry.ex` của dự án Phoenix tiêu chuẩn.
3.  **Tập phân tích Log:** Hiểu cơ chế gom log tập trung (ELK Stack hoặc Loki). Tập viết các câu truy vấn log tìm kiếm lỗi theo Trace ID để trace luồng đi của 1 request qua nhiều microservices.
