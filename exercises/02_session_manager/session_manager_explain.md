# 💡 Exercise Explanation: Dynamic Process Management (`Registry` & `DynamicSupervisor`)

## 1. Real-world Requirements & Design
In large, distributed, real-time systems (such as chat rooms, user sessions, game sessions), we cannot constantly persist state in a Database because the high read/write frequency causes I/O bottlenecks.
Elixir's solution is to run **each User Session as a distinct Process (GenServer)**.

However, we cannot hardcode these processes in the Supervision tree at application startup because we don't know in advance which users will log in. Therefore, we need:
1. **DynamicSupervisor:** To dynamically start worker processes at runtime when a user logs in.
2. **Registry:** Acting as a phone book to map the string `user_id` to the `PID` of the corresponding process to route messages to the right recipient.

---

## 2. Implementation Code Explanation

### 2.1. Dynamic Identification with Via Tuple
To have the GenServer automatically register its name with the Registry upon startup:
```elixir
def via_tuple(user_id) do
  {:via, Registry, {UserRegistry, user_id}}
end

def start_link(user_id) do
  # Register the process name using a via tuple instead of a static module name atom
  GenServer.start_link(__MODULE__, %{}, name: via_tuple(user_id))
end
```
* `{:via, Registry, {registry_name, key}}` is a standard format of the BEAM VM. When you send a message or make a call to this tuple, the BEAM VM automatically looks up the `UserRegistry` to find the actual PID for `user_id` and forwards the message there.

### 2.2. Implementing SessionManager

```elixir
defmodule SessionManager do
  # 1. Start a new dynamic session
  def start_session(user_id) do
    # Instruct the DynamicSupervisor to start a child worker
    case DynamicSupervisor.start_child(UserSessionSupervisor, {SessionWorker, user_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  # 2. Query session data
  def get_session_data(user_id) do
    # Look up the Registry to find the PID of the user_id
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> {:ok, SessionWorker.get_data(pid)}
      [] -> {:error, :not_found}
    end
  end

  # 3. Update session data
  def update_session_data(user_id, key, value) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> {:ok, SessionWorker.put_data(pid, key, value)}
      [] -> {:error, :not_found}
    end
  end

  # 4. Stop session (logout)
  def stop_session(user_id) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> 
        # Use DynamicSupervisor to cleanly terminate the child process
        DynamicSupervisor.terminate_child(UserSessionSupervisor, pid)
        :ok
      [] -> {:error, :not_found}
    end
  end
end
```

---

## 3. Critical Technical Aspects

### 3.1. Why use `DynamicSupervisor.terminate_child/2` instead of `GenServer.stop/1`?
* If you call `GenServer.stop(pid)`, the process will stop. However, if the process is configured with the `restart: :permanent` option (the supervisor's default), the Supervisor will treat this as an unexpected termination and **immediately restart** a brand-new worker session. This makes it impossible for the user to log out.
* Calling `DynamicSupervisor.terminate_child/2` notifies the Supervisor that this is an intentional removal of the child worker from the supervision list, avoiding infinite automatic restarts.
* Setting `restart: :transient` in `SessionWorker` means: the process will only be restarted if it crashes unexpectedly (abnormal exit). If it completes its task and terminates normally (`:normal`), the Supervisor will let it rest and not restart it.

### 3.2. Registry Auto-cleanup
* An extremely powerful feature of Registry in Elixir is that it automatically monitors all processes registered under it.
* If a `SessionWorker` crashes or is stopped due to logout, the Registry automatically detects this and immediately removes the `{user_id => pid}` mapping from its lookup table. We do not need to write any manual cleanup code for the Registry.
