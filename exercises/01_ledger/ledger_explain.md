# 💡 Exercise Explanation: Ledger Transaction (`Ecto.Multi`)

## 1. Real-world Requirements & Design
The problem requires executing a money transfer transaction between 2 accounts and recording a log. In financial (fintech) projects, the most critical aspect is **data integrity (ACID)**. 
If debiting account A succeeds, but crediting account B fails (for example, account B is locked), A's money must not disappear. Conversely, if writing the log fails, the transfer transaction must also be aborted.

Therefore, we need to encapsulate this entire process into a **Database Transaction** using `Ecto.Multi`.

---

## 2. Implementation Code Explanation

```elixir
def transfer_money(from_id, to_id, amount) do
  # 1. Initialize an empty Multi struct
  Ecto.Multi.new()
  
  # 2. Step 1: Debit the sender's account
  |> Ecto.Multi.run(:debit, fn repo, _changes ->
    case repo.get.(from_id) do
      nil -> {:error, "Sender account not found"}
      sender ->
        if sender.balance >= amount do
          new_balance = sender.balance - amount
          updated_state = repo.update_account.(from_id, new_balance)
          # Return the new database state (updated in-memory within the sandbox)
          {:ok, %{sender | balance: new_balance}, updated_state}
        else
          {:error, "Insufficient balance"}
        end
    end
  end)
  
  # 3. Step 2: Credit the receiver's account
  |> Ecto.Multi.run(:credit, fn repo, _changes ->
    case repo.get.(to_id) do
      nil -> {:error, "Receiver account not found"}
      receiver ->
        new_balance = receiver.balance + amount
        updated_state = repo.update_account.(to_id, new_balance)
        {:ok, %{receiver | balance: new_balance}, updated_state}
    end
  end)
  
  # 4. Step 3: Write transaction log
  |> Ecto.Multi.run(:log, fn repo, _changes ->
    {log, updated_state} = repo.insert_log.(from_id, to_id, amount)
    {:ok, log, updated_state}
  end)
  
  # 5. Execute the entire transaction chain via the database connection
  |> MockRepo.transaction()
end
```

---

## 3. Critical Technical Aspects

### 3.1. What parameters does Ecto.Multi.run receive?
Each callback function in `Multi.run` receives two parameters: `fn repo, changes -> ... end`.
*   `repo`: The Database connection module. In a real-world environment, it is `MyApp.Repo`. Passing `repo` directly like this allows Ecto to execute queries within the **Transaction Sandbox** (the current connection occupied by the transaction). If you call `MyApp.Repo.get` directly instead of `repo.get`, you might read data outside the transaction, leading to dirty reads or deadlocks.
*   `changes`: A Map containing the return results of the previous steps. For example, at the `:credit` step, `changes` will be `%{debit: updated_sender_struct}`. You can use this data to make logical decisions for subsequent steps.

### 3.2. How Rollback Works in the Sandbox
*   In MockRepo, we simulate transactions by taking a copy of the database state (`original_state`).
*   When running through each step of the Multi (`:debit` -> `:credit` -> `:log`), if any step returns `{:error, reason}`, the traversal (`Enum.reduce_while`) will immediately stop (`{:halt, ...}`).
*   MockRepo will then discard all temporary states updated by the previous steps, without overwriting the official database Agent state, and return the error. This ensures Atomicity: either all succeed, or no changes are applied.
