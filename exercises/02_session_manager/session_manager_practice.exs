# ==============================================================================
# ADVANCED PRACTICE EXERCISE: DYNAMIC PROCESS MANAGEMENT (REGISTRY & DYNAMICSUPERVISOR)
# ==============================================================================
# Problem: Build a user login session management system.
# Whenever a user logs in, the system will start a GenServer representing that session
# to store temporary information (e.g., shopping cart, tokens) in-memory.
#
# Requirements:
# 1. Use Registry to dynamically register a name for each session process as:
#    `{:via, Registry, {UserRegistry, user_id}}`
# 2. Use DynamicSupervisor to monitor and start session processes dynamically.
# 3. Define the `SessionWorker` module (GenServer) to store session state.
# 4. Define the `SessionManager` module to provide APIs:
#    - `start_session(user_id)`: Start a new session.
#    - `get_session_data(user_id)`: Get current session data.
#    - `update_session_data(user_id, key, value)`: Update session data.
#    - `stop_session(user_id)`: Stop session process when user logs out.
#
# Run this file with the command: elixir session_manager_practice.exs
# ==============================================================================

defmodule SessionWorker do
  use GenServer, restart: :transient

  # Helper to generate via tuple identifier for Registry
  def via_tuple(user_id) do
    {:via, Registry, {UserRegistry, user_id}}
  end

  # --- CLIENT API ---

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, %{}, name: via_tuple(user_id))
  end

  def get_data(pid) do
    GenServer.call(pid, :get_data)
  end

  def put_data(pid, key, value) do
    GenServer.call(pid, {:put_data, key, value})
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(initial_state) do
    {:ok, initial_state}
  end

  @impl true
  def handle_call(:get_data, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:put_data, key, value}, _from, state) do
    new_state = Map.put(state, key, value)
    {:reply, :ok, new_state}
  end
end

defmodule SessionManager do
  @doc """
  Starts a new SessionWorker under DynamicSupervisor (named UserSessionSupervisor).
  If a session already exists for this user_id, returns `{:error, :already_started}`.
  """
  def start_session(user_id) do
    case DynamicSupervisor.start_child(UserSessionSupervisor, {SessionWorker, user_id}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :already_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the current state data of the session for a user_id.
  If the session does not exist, returns `{:error, :not_found}`.
  """
  def get_session_data(user_id) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> {:ok, SessionWorker.get_data(pid)}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Updates the session data for a user_id.
  If the session does not exist, returns `{:error, :not_found}`.
  """
  def update_session_data(user_id, key, value) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] -> {:ok, SessionWorker.put_data(pid, key, value)}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Stops the session process when a user logs out.
  """
  def stop_session(user_id) do
    case Registry.lookup(UserRegistry, user_id) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(UserSessionSupervisor, pid)
        :ok

      [] ->
        {:error, :not_found}
    end
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule SessionManagerTest do
  use ExUnit.Case

  setup do
    # Start Registry and DynamicSupervisor specifically for testing
    start_supervised!({Registry, keys: :unique, name: UserRegistry})
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: UserSessionSupervisor})
    :ok
  end

  test "successfully starts session and retrieves initial empty data" do
    assert {:ok, pid} = SessionManager.start_session("user_123")
    assert is_pid(pid)

    assert {:ok, data} = SessionManager.get_session_data("user_123")
    assert data == %{}
  end

  test "does not allow creating duplicate sessions for the same user" do
    assert {:ok, _pid} = SessionManager.start_session("user_123")
    assert {:error, :already_started} = SessionManager.start_session("user_123")
  end

  test "successfully updates and retrieves session data" do
    assert {:ok, _pid} = SessionManager.start_session("user_456")

    assert {:ok, :ok} =
             SessionManager.update_session_data("user_456", :cart, ["item_1", "item_2"])

    assert {:ok, data} = SessionManager.get_session_data("user_456")
    assert data == %{cart: ["item_1", "item_2"]}
  end

  test "returns error when operating on a non-existent session" do
    assert {:error, :not_found} = SessionManager.get_session_data("non_existent")
    assert {:error, :not_found} = SessionManager.update_session_data("non_existent", :key, "val")
  end

  test "successfully stops session (logout) and terminates process" do
    assert {:ok, _pid} = SessionManager.start_session("user_789")
    assert :ok = SessionManager.stop_session("user_789")
    # Session no longer exists
    assert {:error, :not_found} = SessionManager.get_session_data("user_789")
  end
end
