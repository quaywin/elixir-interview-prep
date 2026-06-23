# ==============================================================================
# BÀI TẬP THỰC HÀNH NGÀY 1: LEDGER TRANSACTION VỚI MOCK ECTO.MULTI
# ==============================================================================
# Đề bài: Thiết kế một hệ thống Ledger (sổ cái) mini.
# Bạn cần xây dựng hàm `transfer_money/3` thực hiện việc chuyển tiền giữa 2 tài khoản.
# Yêu cầu:
# 1. Sử dụng Ecto.Multi để thực hiện giao dịch an toàn.
# 2. Kiểm tra số dư tài khoản gửi (sender), nếu không đủ tiền thì rollback và trả về lỗi.
# 3. Ghi lại lịch sử giao dịch (transaction log) vào database.
# 4. Viết Unit Test để xác minh logic.
#
# Chạy file này bằng lệnh: elixir ledger_practice.exs
# ==============================================================================

# --- MOCK ECTO SYSTEM ---
# Giả lập database và Ecto.Multi để người dùng tập trung vào tư duy logic của Elixir.
defmodule Ecto.Multi do
  def struct, do: %{operations: []}
  def new, do: struct()

  def run(multi, name, fun) do
    %{multi | operations: multi.operations ++ [{name, fun}]}
  end
end

defmodule MockRepo do
  use Agent

  def start_link(initial_state) do
    Agent.start_link(fn -> initial_state end, name: __MODULE__)
  end

  # Lấy trạng thái hiện tại (chỉ đọc)
  def get_state do
    Agent.get(__MODULE__, & &1)
  end

  # Cập nhật toàn bộ trạng thái sau khi transaction thành công
  def commit_state(new_state) do
    Agent.update(__MODULE__, fn _ -> new_state end)
  end

  # Helper functions để truy vấn trong transaction sandbox
  def sandbox_get(state, id) do
    Map.get(state.accounts, id)
  end

  def sandbox_update_account(state, id, new_balance) do
    accounts = Map.update!(state.accounts, id, fn acc -> %{acc | balance: new_balance} end)
    %{state | accounts: accounts}
  end

  def sandbox_insert_log(state, from_id, to_id, amount) do
    log = %{id: length(state.logs) + 1, from_id: from_id, to_id: to_id, amount: amount}
    logs = state.logs ++ [log]
    {log, %{state | logs: logs}}
  end

  # Thực thi chuỗi operations của Ecto.Multi trong một transaction sandbox giả lập
  # Điều này ngăn chặn việc gọi chéo process gây deadlock (process attempted to call itself)
  def transaction(multi) do
    # 1. Lấy bản sao state hiện tại
    original_state = get_state()

    # 2. Chạy các bước Multi trên sandbox state này
    result = Enum.reduce_while(multi.operations, {:ok, original_state, %{}}, fn {name, fun}, {:ok, current_state, acc} ->
      # Tạo một repo wrapper để các callback gọi trực tiếp vào sandbox state thay vì gọi MockRepo qua genserver call
      sandbox_repo = %{
        state: current_state,
        get: fn id -> sandbox_get(current_state, id) end,
        update_account: fn id, bal -> sandbox_update_account(current_state, id, bal) end,
        insert_log: fn from, to, amt -> sandbox_insert_log(current_state, from, to, amt) end
      }

      case fun.(sandbox_repo, acc) do
        {:ok, val, updated_state} -> 
          {:cont, {:ok, updated_state, Map.put(acc, name, val)}}
        {:error, reason} -> 
          {:halt, {:error, name, reason, acc}}
      end
    end)

    # 3. Nếu thành công, commit thay đổi vào Agent thực tế. Nếu thất bại, giữ nguyên state cũ (Rollback)
    case result do
      {:ok, final_state, changes} ->
        commit_state(final_state)
        {:ok, changes}
      {:error, name, reason, changes} ->
        {:error, name, reason, changes}
    end
  end
end

# --- PHẦN BÀI LÀM CỦA BẠN ---
defmodule LedgerService do
  @doc """
  Thực hiện chuyển tiền từ tài khoản `from_id` sang `to_id` với số tiền `amount`.
  Sử dụng Ecto.Multi để gom 3 bước sau vào 1 transaction:
  1. Giảm số dư tài khoản gửi (`from_id`) - key bước: :debit
  2. Tăng số dư tài khoản nhận (`to_id`) - key bước: :credit
  3. Ghi transaction log - key bước: :log
  
  Yêu cầu trả về:
  - `{:ok, %{debit: sender_acc, credit: receiver_acc, log: log_record}}` nếu thành công.
  - `{:error, step_name, reason, accumulated_changes}` nếu thất bại ở bước nào đó.
  
  *Chú ý:* Sử dụng `repo` được truyền vào trong callback của Ecto.Multi.run để thao tác:
    - `repo.get.(id)` -> lấy tài khoản (trả về map tài khoản hoặc nil)
    - `repo.update_account.(id, new_balance)` -> cập nhật số dư, trả về state mới
    - `repo.insert_log.(from_id, to_id, amount)` -> lưu log, trả về {log, state mới}
  """
  def transfer_money(from_id, to_id, amount) do
    # HƯỚNG DẪN: Viết Ecto.Multi pipeline và chạy MockRepo.transaction() ở cuối
    # Các hàm callback của Multi.run nhận 2 tham số: `fn repo, changes -> ... end`
    # Trong đó repo chứa các helper functions, changes chứa kết quả các bước trước đó.
    # Mỗi callback thành công phải trả về: `{:ok, value_tra_ve, updated_state}`
    # Thất bại trả về: `{:error, "lý do"}`
    
    # --- TODO: BẮT ĐẦU VIẾT CODE CỦA BẠN DƯỚI ĐÂY ---
    Ecto.Multi.new()
    # Hãy điền các bước :debit, :credit, :log và gọi MockRepo.transaction()
    # (Ví dụ: |> Ecto.Multi.run(:debit, fn repo, _changes -> ... end))
    # Xem ví dụ đáp án gợi ý ở cuối file nếu gặp khó khăn.
    
    # --- BẮT ĐẦU CODE MẪU BỊ KHUYẾT ---
    # Thay thế phần này bằng code của bạn
    # (Hiện tại trả về lỗi để test suite chạy báo fail trước khi bạn code)
    |> Ecto.Multi.run(:debit, fn _repo, _changes -> {:error, "Chưa được cài đặt"} end)
    |> MockRepo.transaction()
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule LedgerServiceTest do
  use ExUnit.Case

  setup do
    # Thiết lập trạng thái database ban đầu trước mỗi test case
    accounts = %{
      1 => %{id: 1, name: "Alice", balance: 1000},
      2 => %{id: 2, name: "Bob", balance: 500}
    }
    start_supervised!({MockRepo, %{accounts: accounts, logs: []}})
    :ok
  end

  test "chuyển tiền thành công giữa 2 tài khoản" do
    assert {:ok, changes} = LedgerService.transfer_money(1, 2, 300)
    
    # Kiểm tra số dư mới trong DB
    state = MockRepo.get_state()
    assert Map.get(state.accounts, 1).balance == 700
    assert Map.get(state.accounts, 2).balance == 800
    
    # Kiểm tra kết quả trả về từ Ecto.Multi
    assert changes.debit.balance == 700
    assert changes.credit.balance == 800
    assert changes.log.from_id == 1
    assert changes.log.to_id == 2
    assert changes.log.amount == 300
  end

  test "thất bại khi tài khoản gửi không đủ số dư (không được thay đổi số dư DB)" do
    assert {:error, :debit, "Insufficient balance", _changes} = LedgerService.transfer_money(1, 2, 2000)
    
    # Kiểm tra số dư DB không bị thay đổi (Rollback hoạt động đúng)
    state = MockRepo.get_state()
    assert Map.get(state.accounts, 1).balance == 1000
    assert Map.get(state.accounts, 2).balance == 500
  end

  test "thất bại khi tài khoản gửi không tồn tại" do
    assert {:error, :debit, "Sender account not found", _changes} = LedgerService.transfer_money(99, 2, 100)
  end

  test "thất bại khi tài khoản nhận không tồn tại (Rollback cả bước debit trước đó)" do
    assert {:error, :credit, "Receiver account not found", _changes} = LedgerService.transfer_money(1, 99, 100)
    
    # Đảm bảo tài khoản 1 không bị trừ tiền do bước 2 lỗi và rollback toàn bộ
    state = MockRepo.get_state()
    assert Map.get(state.accounts, 1).balance == 1000
  end
end

# ==============================================================================
# HƯỚNG DẪN / ĐÁP ÁN GỢI Ý (ĐỪNG XÓA DÒNG NÀY ĐỂ BẠN CÓ THỂ XEM KHI CẦN)
# ==============================================================================
# def transfer_money(from_id, to_id, amount) do
#   Ecto.Multi.new()
#   |> Ecto.Multi.run(:debit, fn repo, _changes ->
#     case repo.get.(from_id) do
#       nil -> {:error, "Sender account not found"}
#       sender ->
#         if sender.balance >= amount do
#           new_balance = sender.balance - amount
#           updated_state = repo.update_account.(from_id, new_balance)
#           {:ok, %{sender | balance: new_balance}, updated_state}
#         else
#           {:error, "Insufficient balance"}
#         end
#     end
#   end)
#   |> Ecto.Multi.run(:credit, fn repo, _changes ->
#     case repo.get.(to_id) do
#       nil -> {:error, "Receiver account not found"}
#       receiver ->
#         new_balance = receiver.balance + amount
#         updated_state = repo.update_account.(to_id, new_balance)
#         {:ok, %{receiver | balance: new_balance}, updated_state}
#     end
#   end)
#   |> Ecto.Multi.run(:log, fn repo, _changes ->
#     {log, updated_state} = repo.insert_log.(from_id, to_id, amount)
#     {:ok, log, updated_state}
#   end)
#   |> MockRepo.transaction()
# end
