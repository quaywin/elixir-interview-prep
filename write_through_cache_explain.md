# 💡 Giải Thích Bài Tập: Write-Through Cache (`ETS` & `GenServer`)

## 1. Yêu Cầu Thực Tế & Thiết Kế
Trong các hệ thống có lượng truy cập siêu lớn (High Throughput), ví dụ như API Gateway, User Session validator, Product Catalog, số lượng request đọc dữ liệu luôn gấp hàng chục tới hàng trăm lần request ghi dữ liệu.
Nếu tất cả các request đọc đều phải gửi message qua một GenServer duy nhất, GenServer đó sẽ bị nghẽn (bottleneck) do xử lý mailbox tuần tự.

**Giải pháp:**
*   Sử dụng **ETS (Erlang Term Storage)** để lưu cache in-memory. Bảng ETS được cấu hình ở chế độ `:protected`.
*   **Thao tác đọc (Read):** Thực hiện trực tiếp trên context của caller process (như Phoenix Controller) bằng cách gọi thẳng vào bộ nhớ của bảng ETS. Hoàn toàn không đi qua GenServer mailbox. Nhiều process có thể đọc bảng ETS này song song 100%.
*   **Thao tác ghi (Write):** Bắt buộc phải gửi message qua GenServer `CacheService`. GenServer này sẽ thực hiện ghi đồng bộ xuống Database trước để đảm bảo dữ liệu được lưu vĩnh viễn (Persisted), sau đó mới cập nhật lại dữ liệu mới vào bảng ETS cache.

---

## 2. Giải Thích Code Triển Khai

### 2.1. Đọc Trực Tiếp Từ Caller Context (Không qua GenServer)
```elixir
def read(key) do
  # Hàm này được thực thi bởi chính process gọi nó (ví dụ: Task hoặc Web Connection process)
  case :ets.lookup(@table_name, key) do
    [{^key, value}] -> {:ok, value}
    [] -> {:error, :not_found}
  end
end
```
*   Nhờ cơ chế này, tốc độ đọc gần như đạt mức tối đa của RAM (~vài triệu lượt đọc/giây). GenServer `CacheService` hoàn toàn rảnh rỗi để tập trung xử lý các việc khác.

### 2.2. Giao Dịch Ghi Đồng Bộ Qua GenServer Owner
```elixir
# Khởi tạo bảng ETS trong init/1 của GenServer
def init(_opts) do
  # :set -> Cấu trúc Key-Value độc nhất
  # :protected -> Chỉ Owner process (GenServer này) được ghi, các process khác chỉ được đọc
  # :named_table -> Cho phép dùng tên atom :CacheTable thay vì quản lý qua tid (Table ID)
  :ets.new(@table_name, [:set, :protected, :named_table])
  {:ok, %{}}
end

# Xử lý transaction ghi
def handle_call({:write, key, value}, _from, state) do
  # 1. Ghi dữ liệu xuống DB trước
  case MockDB.write(key, value) do
    :ok ->
      # 2. Ghi DB thành công -> ghi đè vào cache ETS
      :ets.insert(@table_name, {key, value})
      {:reply, :ok, state}
    
    _error ->
      {:reply, {:error, :db_write_failed}, state}
  end
end
```

---

## 3. Các Điểm Quan Trọng Dưới Góc Nhìn Kỹ Thuật

### 3.1. Tại sao bảng ETS phải cấu hình `:protected`?
*   `:private`: Chỉ duy nhất Owner process được đọc và ghi. Các process khác gọi `:ets.lookup` sẽ bị crash với lỗi `:badarg`. Không thể dùng làm cache dùng chung.
*   `:public`: Bất kỳ process nào cũng được đọc và ghi. Dễ dẫn đến tình trạng **Race Condition** dữ liệu (ví dụ: Process A đọc DB ghi đè giá trị cũ vào ETS ngay lúc Process B đang ghi giá trị mới).
*   `:protected`: Đảm bảo tính nhất quán cao nhất. Chỉ có GenServer `CacheService` mới có quyền thay đổi dữ liệu bảng ETS sau khi đã đảm bảo ghi thành công xuống Database. Tất cả các process khác chỉ có quyền đọc dữ liệu tĩnh, loại bỏ hoàn toàn khả năng xung đột ghi dữ liệu.

### 3.2. Vấn đề Cache Invalidation (Hủy Cache)
Trong thiết kế Write-Through:
*   Dữ liệu luôn được ghi vào DB và Cache đồng thời, nên Cache không bao giờ bị lệch dữ liệu so với DB (Strong consistency).
*   Tuy nhiên, nếu Database bị thay đổi trực tiếp bên ngoài (ví dụ: quản trị viên sửa DB bằng tay), Cache sẽ bị out-of-date (lệch dữ liệu). 
*   *Cách khắc phục:* Cần có cơ chế lắng nghe sự kiện thay đổi của database (CDC - Change Data Capture) hoặc thiết lập thời gian hết hạn (TTL - Time To Live) cho từng bản ghi trong ETS để tự động xóa sau một khoảng thời gian.
