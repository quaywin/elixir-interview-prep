# 🗺️ Cẩm Nang Luyện Tập: Thiết Kế Hệ Thống (System Design Cookbook)

Đối với vị trí Senior Engineer, vòng System Design không kiểm tra xem bạn có nhớ cú pháp code hay không, mà kiểm tra khả năng **nhìn bức tranh toàn cảnh (bird's-eye view)**, **phân tích tải (back-of-the-envelope estimation)**, và đưa ra quyết định **đánh đổi (trade-offs)** một cách logic.

Tài liệu này cung cấp khung sườn (framework) chuẩn để trả lời và các kịch bản thiết kế hệ thống thực tế.

---

## 1. Khung Sườn 4 Bước Trả Lời Mọi Bài Toán System Design

Khi nhận đề bài (ví dụ: *"Thiết kế hệ thống Uber"* hoặc *"Thiết kế hệ thống Chat"*), tuyệt đối không được lao vào vẽ sơ đồ ngay. Hãy đi theo đúng 4 bước sau:

```
+-----------------------------------------------------------------+
| Bước 1: Thu thập yêu cầu (Clarifying Requirements)              |
| - Yêu cầu chức năng: User làm được gì?                          |
| - Yêu cầu phi chức năng: Scale bao nhiêu CCU? Độ trễ? Availability?|
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| Bước 2: Thiết kế tổng quan (High-Level Design)                  |
| - Xác định các Service cốt lõi (Auth, API Gateway, App Node)    |
| - Luồng đi của dữ liệu chính (Client -> LB -> Server -> DB)     |
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| Bước 3: Thiết kế chi tiết (Deep Dive)                           |
| - Chọn Database: SQL hay NoSQL? Tại sao? Schema thế nào?       |
| - Chọn Message Broker: Kafka hay RabbitMQ?                      |
| - Lưu trữ cache: Redis hay ETS?                                 |
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| Bước 4: Khả năng mở rộng & Chịu lỗi (Scale & Bottlenecks)       |
| - Chuyện gì xảy ra nếu 1 node chết? (Failover/Replication)      |
| - Giải quyết nghẽn mạng (Thundering herd, Rate limiting)        |
+-----------------------------------------------------------------+
```

---

## 2. Kịch Bản Thiết Kế Thực Tế 1: Hệ thống Đấu giá trực tuyến (Online Auction System)

*   **Yêu cầu:** Cho phép hàng triệu người dùng xem và đặt giá cho các vật phẩm đấu giá theo thời gian thực (Real-time bidding). Lịch sử đặt giá phải chính xác tuyệt đối. Giá trị cao nhất phải được cập nhật ngay lập tức xuống màn hình tất cả người dùng khác.

### 2.1. Đánh giá tải lượng (Estimations)
*   **Scale:** 10 triệu người dùng hoạt động mỗi ngày (DAU).
*   **CCU (Concurrent Users):** Giả sử lúc cao điểm (phút cuối của phiên đấu giá) có 100,000 người dùng truy cập đồng thời vào một vật phẩm cực hot.
*   **Write rate (Đặt giá):** 10,000 lượt đặt giá/giây.
*   **Read rate (Xem giá):** 100,000 lượt đọc/giây.

### 2.2. Kiến trúc giải pháp (High-Level Design)

```
[ Client / Browser ] <--- (WebSocket / Phoenix Channels) ---+
       |                                                    |
   (HTTPS / Bid Request)                                    |
       v                                                    |
  [ API Gateway ]                                           |
       |                                                    |
       v                                                    |
  [ App Service Nodes ] (Elixir Cluster)                    |
       |                                                    |
       +---> [ ETS / Redis Cache ] (Lưu giá cao nhất hiện tại)|
       |                                                    |
       +---> [ Kafka / Message Queue ]                      |
                   |                                        |
                   v                                        |
             [ Database Worker ]                            |
                   | (Atomic Update DB)                     |
                   v                                        |
             [ PostgreSQL ] (Lưu lịch sử đấu giá chính thức)  |
```

### 2.3. Các quyết định đánh đổi & Lựa chọn kỹ thuật (Trade-offs)

1.  **WebSocket vs HTTP Polling cho việc hiển thị giá mới:**
    *   *HTTP Polling (Dumb client liên tục gọi API mỗi 1s):* Dễ làm, không tốn RAM duy trì socket. Nhưng sẽ làm sập server do lượng HTTP overhead quá lớn (100k requests/s).
    *   *WebSockets (Phoenix Channels):* Client duy trì 1 kết nối duy nhất. Server push trực tiếp khi có giá mới. Elixir quản lý WebSocket cực tốt (100k connections chỉ tốn ~200MB RAM). -> **Lựa chọn: WebSockets**.
2.  **Xử lý Race Condition khi đặt giá (Concurrency Conflict):**
    *   *Vấn đề:* Hai người dùng cùng đặt giá $100$ USD cho một vật phẩm đang có giá $99$ USD tại cùng một mili-giây. Hệ thống chỉ được chấp nhận 1 người và từ chối người còn lại.
    *   *Giải pháp 1 (Optimistic Locking ở DB):* Dùng version check ở Database. Nếu DB cập nhật thất bại -> báo lỗi cho user. Nhưng việc này tạo ra hàng nghìn lệnh ghi thất bại xuống DB đĩa cứng, gây nghẽn DB.
    *   *Giải pháp 2 (GenServer Actor Model):* Mỗi vật phẩm đấu giá hoạt động sẽ được quản lý bởi một GenServer duy nhất trong Cluster (sử dụng Registry để tìm PID). Mọi yêu cầu đặt giá cho vật phẩm này phải gửi qua GenServer đó. Vì GenServer xử lý mailbox tuần tự, nó sẽ chấp nhận yêu cầu đến trước, cập nhật cache in-memory, và từ chối ngay yêu cầu đến sau mà không cần gọi xuống Database -> **Lựa chọn: Actor Model (GenServer)** để làm chốt chặn concurrency tầng App, sau đó lưu bất đồng bộ xuống DB qua Queue.

---

## 3. Kịch Bản Thiết Kế Thực Tế 2: Hệ thống đẩy tin nhắn diện rộng (Mass Notification Push)

*   **Yêu cầu:** Gửi tin nhắn khẩn cấp (như thông tin khuyến mãi hoặc cảnh báo thiên tai) tới 5 triệu người dùng trong vòng tối đa 1 phút thông qua App Push Notification (APNS/FCM) và WebSockets.

### 3.1. Các vấn đề cốt lõi cần giải quyết
1.  **Giới hạn băng thông API của bên thứ ba (FCM/APNS Rate Limits):** Apple và Google có giới hạn số lượng request push gửi lên server của họ mỗi giây. Nếu gửi quá nhanh, tài khoản của bạn sẽ bị block hoặc bị trễ tin nhắn.
2.  **Khả năng chịu lỗi khi sập mạng:** Nếu đang gửi dở dang đến triệu thứ 2 mà server bị crash, làm sao để khi restart, hệ thống biết để gửi tiếp từ triệu thứ 3 mà không gửi trùng lặp lại cho 2 triệu người đầu tiên?

### 3.2. Thiết kế chi tiết (Deep Dive)
*   **Broadway & GenStage để điều phối Backpressure:**
    *   Lưu danh sách 5 triệu user cần gửi vào một Message Broker (như Kafka).
    *   Sử dụng Elixir Broadway làm Consumer. Broadway sẽ điều chỉnh thông số `max_demand` để kiểm soát chính xác tốc độ đọc từ Kafka khớp với Rate limit của Google/Apple APIs.
*   **Stateful Tracking (Đánh vết trạng thái):**
    *   Không gửi message dạng fire-and-forget thô. Mỗi job gửi tin nhắn được gắn một `UUID`.
    *   Sử dụng một KV Store nhanh (như Redis hoặc Postgres với Index) để lưu trạng thái của từng `UUID` (`pending`, `processing`, `sent`, `failed`).
    *   Khi worker gửi thành công, cập nhật trạng thái sang `sent`. Nếu worker bị sập giữa chừng, sau khi restart, hệ thống chỉ cần truy vấn các `UUID` có trạng thái `pending` trong Kafka partition để tiếp tục xử lý.

---

## 💡 Hướng Dẫn Luyện Tập System Design
1.  **Luyện viết sơ đồ khối (Architectural Diagrams):** Hãy tập vẽ các sơ đồ thiết kế hệ thống trên giấy hoặc các công cụ trực tuyến (Excalidraw/draw.io). Tập trung chỉ rõ: Đâu là App Node, đâu là Cache, đâu là Database, và hướng đi của data flows.
2.  **Tập trả lời các câu hỏi tại sao (Why?):** Đừng nói *"Tôi chọn PostgreSQL"*. Hãy nói *"Tôi chọn PostgreSQL vì chúng ta cần đảm bảo tính toàn vẹn ACID cao cho lịch sử giao dịch và dữ liệu không có tính chất thay đổi cấu trúc liên tục như NoSQL"*.
