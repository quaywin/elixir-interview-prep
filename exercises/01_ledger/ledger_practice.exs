# ==============================================================================
# DAY 1 PRACTICE EXERCISE: LEDGER TRANSACTION WITH MOCK ECTO.MULTI
# ==============================================================================
# Problem: Design a mini Ledger system.
# You need to implement the `transfer_money/3` function to transfer money between 2 accounts.
# Requirements:
# 1. Use Ecto.Multi to execute transaction safely.
# 2. Check the sender account's balance; if insufficient, rollback and return an error.
# 3. Record a transaction log into the database.
# 4. Write Unit Tests to verify logic.
#
# Run this file with the command: elixir ledger_practice.exs
# ==============================================================================

# --- MOCK ECTO SYSTEM ---
# Simulate database and Ecto.Multi to help users focus on Elixir logic.
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

  # Get the current state (read-only)
  def get_state do
    Agent.get(__MODULE__, & &1)
  end

  # Update the entire state after a successful transaction
  def commit_state(new_state) do
    Agent.update(__MODULE__, fn _ -> new_state end)
  end

  # Helper functions to query in the transaction sandbox
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

  # Execute the operations chain of Ecto.Multi inside a simulated transaction sandbox
  # This prevents cross-process calls that cause deadlock (process attempted to call itself)
  def transaction(multi) do
    # 1. Get a copy of the current state
    original_state = get_state()

    # 2. Run Multi steps on this sandbox state
    result =
      Enum.reduce_while(multi.operations, {:ok, original_state, %{}}, fn {name, fun},
                                                                         {:ok, current_state, acc} ->
        # Create a repo wrapper so that callbacks directly invoke the sandbox state instead of calling MockRepo via genserver call
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

    # 3. If successful, commit changes to the actual Agent. If failed, keep original state (Rollback)
    case result do
      {:ok, final_state, changes} ->
        commit_state(final_state)
        {:ok, changes}

      {:error, name, reason, changes} ->
        {:error, name, reason, changes}
    end
  end
end

# --- COMPLETED IMPLEMENTATION ---
defmodule LedgerService do
  @doc """
  Transfer money from account `from_id` to `to_id` with the amount `amount`.
  Use Ecto.Multi to group the following 3 steps into a single transaction:
  1. Decrease the balance of the sender account (`from_id`) - step key: :debit
  2. Increase the balance of the receiver account (`to_id`) - step key: :credit
  3. Record a transaction log - step key: :log

  Required return values:
  - `{:ok, %{debit: sender_acc, credit: receiver_acc, log: log_record}}` on success.
  - `{:error, step_name, reason, accumulated_changes}` on failure at any step.
  """
  def transfer_money(from_id, to_id, amount) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:debit, fn repo, _changes ->
      case repo.get.(from_id) do
        nil ->
          {:error, "Sender account not found"}

        sender ->
          if sender.balance >= amount do
            new_balance = sender.balance - amount
            updated_state = repo.update_account.(from_id, new_balance)
            {:ok, %{sender | balance: new_balance}, updated_state}
          else
            {:error, "Insufficient balance"}
          end
      end
    end)
    |> Ecto.Multi.run(:credit, fn repo, _changes ->
      case repo.get.(to_id) do
        nil ->
          {:error, "Receiver account not found"}

        receiver ->
          new_balance = receiver.balance + amount
          updated_state = repo.update_account.(to_id, new_balance)
          {:ok, %{receiver | balance: new_balance}, updated_state}
      end
    end)
    |> Ecto.Multi.run(:log, fn repo, _changes ->
      {log, updated_state} = repo.insert_log.(from_id, to_id, amount)
      {:ok, log, updated_state}
    end)
    |> MockRepo.transaction()
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule LedgerServiceTest do
  use ExUnit.Case

  setup do
    # Set up the initial database state before each test case
    accounts = %{
      1 => %{id: 1, name: "Alice", balance: 1000},
      2 => %{id: 2, name: "Bob", balance: 500}
    }

    start_supervised!({MockRepo, %{accounts: accounts, logs: []}})
    :ok
  end

  test "successfully transfers money between 2 accounts" do
    assert {:ok, changes} = LedgerService.transfer_money(1, 2, 300)

    # Verify new balances in the DB
    state = MockRepo.get_state()
    assert Map.get(state.accounts, 1).balance == 700
    assert Map.get(state.accounts, 2).balance == 800

    # Verify returned results from Ecto.Multi
    assert changes.debit.balance == 700
    assert changes.credit.balance == 800
    assert changes.log.from_id == 1
    assert changes.log.to_id == 2
    assert changes.log.amount == 300
  end

  test "fails when sender account has insufficient balance (DB balances must remain unchanged)" do
    assert {:error, :debit, "Insufficient balance", _changes} =
             LedgerService.transfer_money(1, 2, 2000)

    # Verify DB balances are unchanged (Rollback works correctly)
    state = MockRepo.get_state()
    assert Map.get(state.accounts, 1).balance == 1000
    assert Map.get(state.accounts, 2).balance == 500
  end

  test "fails when sender account does not exist" do
    assert {:error, :debit, "Sender account not found", _changes} =
             LedgerService.transfer_money(99, 2, 100)
  end

  test "fails when receiver account does not exist (Rollbacks the preceding debit step)" do
    assert {:error, :credit, "Receiver account not found", _changes} =
             LedgerService.transfer_money(1, 99, 100)

    # Ensure account 1 is not debited because step 2 failed and the entire transaction rolled back
    state = MockRepo.get_state()
    assert Map.get(state.accounts, 1).balance == 1000
  end
end
