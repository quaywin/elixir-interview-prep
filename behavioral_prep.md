# 🤝 Cẩm Nang Luyện Tập: Phỏng Vấn Hành Vi & Dẫn Dắt (Behavioral & Leadership)

Interviewer muốn kiểm tra xem bạn có phải là một **Senior thực thụ (về cả mặt con người và kỹ năng mềm)** hay chỉ là một lập trình viên biết viết code lâu năm. 

Tài liệu này hướng dẫn bạn cách xây dựng các câu chuyện của riêng mình theo mô hình **STAR** chuẩn mực để trả lời các câu hỏi tình huống.

---

## 1. Công Thức STAR: Cách Kể Một Câu Chuyện Cuốn Hút

Mỗi câu trả lời của bạn nên kéo dài từ **2 đến 3 phút** và bắt buộc phải đi qua 4 phần sau:

```
+-----------------------------------------------------------------+
| S - Situation (Bối cảnh): 15% thời gian                         |
| - Dự án gì? Vấn đề nghiêm trọng gì xảy ra? Ai liên quan?         |
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| T - Task (Nhiệm vụ của bạn): 15% thời gian                      |
| - Vai trò của bạn là gì? Mục tiêu cụ thể cần đạt được?           |
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| A - Action (Hành động của bạn): 50% thời gian                   |
| - BẠN đã làm gì? (Dùng ngôi "Tôi" thay vì "Chúng tôi")           |
| - Phân tích kỹ thuật, đưa ra giải pháp, thuyết phục mọi người.  |
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| R - Result (Kết quả đạt được): 20% thời gian                    |
| - Kết quả đo lường được (số liệu cụ thể: giảm % CPU, tăng CCU). |
| - Bài học kinh nghiệm rút ra là gì?                             |
+-----------------------------------------------------------------+
```

---

## 2. Kịch Bản STAR 1: Giải Quyết Bất Đồng Ý Kiến Kỹ Thuật (Conflict Resolution)

*   **Tình huống thường gặp:** Team Lead hoặc một đồng nghiệp muốn dùng một tech stack/giải pháp khác với bạn (ví dụ: họ muốn dùng NodeJS cho một service real-time vì họ quen tay, bạn muốn dùng Elixir vì nó phù hợp hơn).
*   **Cách kể câu chuyện chuẩn Senior:**
    *   **S:** Trong dự án XYZ, chúng tôi cần xây dựng một microservice quản lý luồng dữ liệu GPS thời gian thực từ 50,000 thiết bị gửi về liên tục. Một thành viên cốt cựu trong team đề xuất dùng NodeJS kết hợp Express và Redis để lưu state tạm thời. Tôi nhận thấy giải pháp này sẽ tạo ra lượng I/O rất lớn tới Redis và khó quản lý trạng thái kết nối độc lập.
    *   **T:** Nhiệm vụ của tôi là đề xuất phương án tối ưu hơn (sử dụng Elixir/OTP) nhưng phải thuyết phục được đồng nghiệp đó và Tech Lead mà không tạo ra xung đột cá nhân trong team.
    *   **A:** Thay vì tranh cãi lý thuyết, tôi đã làm các bước sau:
        1.  Tôi chủ động hẹn một buổi họp ngắn để lắng nghe lý do của họ (họ chọn Node vì team quen tay, dễ bảo trì). Tôi ghi nhận sự lo ngại đó.
        2.  Tôi dành ra 1 ngày cuối tuần để tự viết một bản chạy thử mẫu (PoC - Proof of Concept) bằng cả hai ngôn ngữ: NodeJS và Elixir.
        3.  Tôi chạy benchmark mô phỏng tải 10,000 requests/giây. Kết quả cho thấy NodeJS ngốn 1.2GB RAM và CPU chạy ở mức 85% kèm latency spike, trong khi Elixir chỉ ngốn 150MB RAM, CPU 12% và latency cực kỳ ổn định nhờ cơ chế concurrency của BEAM VM.
        4.  Tôi trình bày kết quả benchmark khách quan cho team xem, đồng thời cam kết tôi sẽ là người viết tài liệu hướng dẫn (documentation) chi tiết và hỗ trợ support 24/7 cho các thành viên khác trong team làm quen với Elixir.
    *   **R:** Team đồng thuận 100% sử dụng giải pháp Elixir. Service chạy ổn định trên production suốt 1 năm mà không gặp bất kỳ sự cố nghẽn tải nào, giúp tiết kiệm 70% chi phí hạ tầng server của dự án.

---

## 3. Kịch Bản STAR 2: Dẫn Dắt & Mentoring Cho Junior (Technical Leadership)

*   **Tình huống thường gặp:** Team nhận thêm thành viên mới (hoặc Junior) chưa từng làm việc với lập trình hàm (Functional Programming) và họ liên tục viết code Elixir theo phong cách hướng đối tượng (OOP) gây lỗi bộ nhớ hoặc khó bảo trì.
*   **Cách kể câu chuyện chuẩn Senior:**
    *   **S:** Một Junior chuyển từ dự án Ruby on Rails sang dự án Elixir/Phoenix của team tôi. Trong 2 tuần đầu, bạn ấy liên tục tạo ra các class-like structures, sử dụng quá nhiều biến tạm thời và viết các đoạn code lặp lồng nhau sâu (nested conditions) thay vì dùng pipeline `|>` và Pattern Matching. Code review của bạn ấy có tới hơn 30 comments sửa đổi mỗi pull request.
    *   **T:** Tôi cần giúp bạn ấy hiểu cách tư duy lập trình hàm và giảm số lượng lỗi code review mà không làm bạn ấy bị nản lòng hoặc mất tự tin.
    *   **A:** Tôi đã thực hiện các hành động cụ thể:
        1.  Tôi thiết lập các buổi **Pair Programming (lập trình cặp)** 1 tiếng mỗi ngày. Tôi và bạn ấy cùng giải quyết các task thực tế. Tôi trực tiếp chỉ ra cách chuyển đổi từ tư duy "làm thế nào" (imperative) sang "dữ liệu đi về đâu" (declarative/pipeline).
        2.  Tôi viết một bộ **Coding Guidelines** nhỏ cho team, mô tả chi tiết các pattern chuẩn trong Elixir (như cách dùng `with`, cách viết đệ quy đuôi, cách dùng map/reduce).
        3.  Khi review code, tôi chuyển từ cách nhận xét phán xét sang đặt câu hỏi gợi mở, ví dụ: *"Đoạn code này nếu dùng pattern matching trên tham số thì trông sẽ thế nào?"* hoặc *"Bạn có nghĩ đến trường hợp biến này bị thay đổi cấu trúc không?"*.
    *   **R:** Sau 1 tháng, bạn ấy đã tự tin viết code thuần thục theo phong cách Functional Programming. Số lượng comments trong code review giảm từ 30 xuống dưới 5 mỗi PR. Bạn ấy đã có thể tự độc lập hoàn thành các task khó và sau đó tiếp tục mentor lại cho các thành viên mới khác.

---

## 💡 Hướng Dẫn Luyện Tập Behavioral
1.  **Viết ra giấy:** Hãy dành 1 tiếng để viết ra ít nhất **3 câu chuyện thực tế** của bản thân tương ứng với 3 chủ đề: (1) Sửa sự cố production, (2) Xung đột ý kiến kỹ thuật, (3) Mentor đồng nghiệp.
2.  **Luyện nói trước gương:** Tập kể các câu chuyện này một cách tự nhiên. Chú ý tập trung mô tả vào **hành động của riêng bạn (Action)** và **kết quả cụ thể đo lường được (Result)**. Tránh nói chung chung kiểu *"Team chúng tôi đã làm rất tốt"*.
