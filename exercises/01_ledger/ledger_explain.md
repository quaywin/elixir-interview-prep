# 💡 Giải Thích Bài Tập: Ledger Transaction (`Ecto.Multi`)

## 1. Yêu Cầu Thực Tế & Thiết Kế
Bài toán yêu cầu thực hiện giao dịch chuyển tiền giữa 2 tài khoản và ghi log. Trong các dự án tài chính (fintech), điều quan trọng nhất là tính **toàn vẹn dữ liệu (ACID)**. 
Nếu trừ tiền tài khoản A thành công, nhưng cộng tiền cho B thất bại (ví dụ: tài khoản B bị khóa), tiền của A không được phép biến mất. Ngược lại, nếu ghi log lỗi, giao dịch chuyển tiền cũng phải được hủy.

Do đó, chúng ta cần đóng gói toàn bộ quy trình này vào một **Database Transaction** sử dụng `Ecto.Multi`.

---

## 2. Giải Thích Code Triển Khai

```elixir
def transfer_money(from_id, to_id, amount) do
  # 1. Khởi tạo một Multi struct trống
  Ecto.Multi.new()
  
  # 2. Bước 1: Trừ tiền tài khoản gửi
  |> Ecto.Multi.run(:debit, fn repo, _changes ->
    case repo.get.(from_id) do
      nil -> {:error, "Sender account not found"}
      sender ->
        if sender.balance >= amount do
          new_balance = sender.balance - amount
          updated_state = repo.update_account.(from_id, new_balance)
          # Trả về state mới của database (đã được cập nhật in-memory trong sandbox)
          {:ok, %{sender | balance: new_balance}, updated_state}
        else
          {:error, "Insufficient balance"}
        end
    end
  end)
  
  # 3. Bước 2: Cộng tiền tài khoản nhận
  |> Ecto.Multi.run(:credit, fn repo, _changes ->
    case repo.get.(to_id) do
      nil -> {:error, "Receiver account not found"}
      receiver ->
        new_balance = receiver.balance + amount
        updated_state = repo.update_account.(to_id, new_balance)
        {:ok, %{receiver | balance: new_balance}, updated_state}
    end
  end)
  
  # 4. Bước 3: Ghi transaction log
  |> Ecto.Multi.run(:log, fn repo, _changes ->
    {log, updated_state} = repo.insert_log.(from_id, to_id, amount)
    {:ok, log, updated_state}
  end)
  
  # 5. Thực thi toàn bộ chuỗi transaction thông qua database connection
  |> MockRepo.transaction()
end
```

---

## 3. Các Điểm Quan Trọng Dưới Góc Nhìn Kỹ Thuật

### 3.1. Ecto.Multi.run Nhận Tham Số Gì?
Mỗi hàm callback trong `Multi.run` nhận hai tham số: `fn repo, changes -> ... end`.
*   `repo`: Là module kết nối Database. Trong môi trường thực tế, nó là `MyApp.Repo`. Việc sử dụng `repo` truyền trực tiếp này giúp Ecto thực thi truy vấn bên trong **Transaction Sandbox** (kết nối hiện tại đã được chiếm giữ bởi transaction). Nếu bạn gọi thẳng `MyApp.Repo.get` thay vì `repo.get`, bạn có thể đang đọc dữ liệu bên ngoài transaction, dẫn đến tình trạng đọc bẩn (dirty read) hoặc deadlock.
*   `changes`: Là một Map chứa kết quả trả về của các bước trước đó. Ví dụ: ở bước `:credit`, `changes` sẽ là `%{debit: updated_sender_struct}`. Bạn có thể sử dụng dữ liệu này để đưa ra quyết định logic cho các bước sau.

### 3.2. Cơ Chế Hoạt Động Của Rollback Trong Sandbox
*   Trong MockRepo, chúng ta giả lập transaction bằng cách lấy bản sao của database state (`original_state`).
*   Khi chạy qua từng bước của Multi (`:debit` -> `:credit` -> `:log`), nếu có bất kỳ bước nào trả về `{:error, reason}`, quá trình duyệt (`Enum.reduce_while`) sẽ lập tức dừng lại (`{:halt, ...}`).
*   MockRepo lúc này sẽ hủy bỏ (discard) toàn bộ state tạm thời đã cập nhật của các bước trước đó, không ghi đè vào database Agent chính thức và trả về lỗi. Điều này đảm bảo tính nguyên tử (Atomicity): hoặc tất cả thành công, hoặc không có gì thay đổi.
