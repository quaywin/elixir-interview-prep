# ==============================================================================
# PRACTICAL EXERCISE DAY 2: GENSERVER RATE LIMITER
# ==============================================================================
# Objective: Build a GenServer named `RateLimiter` to rate-limit the number of requests
# from each IP.
# Requirements:
# 1. The GenServer accepts configuration parameters upon startup:
#    - `max_requests`: The maximum number of allowed requests in a cycle (e.g., 5 requests)
#    - `interval`: The duration of the cycle in milliseconds (e.g., 5000ms = 5 seconds)
# 2. Define the client API function `request(ip)` which makes a synchronous call (handle_call) to the GenServer:
#    - Returns `{:ok, current_count}` if the IP has not exceeded the limit.
#    - Returns `{:error, :rate_limited}` if the IP has exceeded `max_requests`.
# 3. Must automatically reset the request counts (clear counters) for each IP after the `interval` has elapsed.
#    (Hint: Use `:erlang.send_after/3` to send a message periodically or whenever a new IP appears).
# 4. Write ExUnit test cases to validate your solution.
#
# Run this file with the command: elixir rate_limiter_practice.exs
# ==============================================================================

defmodule RateLimiter do
  use GenServer

  # --- CLIENT API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Sends a request from a specific IP.
  Returns:
  - `{:ok, current_count}` if accepted.
  - `{:error, :rate_limited}` if the limit is exceeded.
  """
  def request(ip) do
    GenServer.call(__MODULE__, {:request, ip})
  end

  # --- SERVER CALLBACKS ---

  @impl true
  def init(opts) do
    max_requests = Keyword.get(opts, :max_requests, 5)
    interval = Keyword.get(opts, :interval, 5000)

    state = %{
      max_requests: max_requests,
      interval: interval,
      ips: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:request, ip}, _from, state) do
    current_count = Map.get(state.ips, ip, 0)

    if current_count >= state.max_requests do
      {:reply, {:error, :rate_limited}, state}
    else
      new_count = current_count + 1
      new_ips = Map.put(state.ips, ip, new_count)

      # If this is the first request from this IP, set up a timer to reset the IP
      if current_count == 0 do
        :erlang.send_after(state.interval, self(), {:reset_ip, ip})
      end

      {:reply, {:ok, new_count}, %{state | ips: new_ips}}
    end
  end

  @impl true
  def handle_info({:reset_ip, ip}, state) do
    new_ips = Map.delete(state.ips, ip)
    {:noreply, %{state | ips: new_ips}}
  end
end

# --- UNIT TEST SUITE ---
ExUnit.start()

defmodule RateLimiterTest do
  use ExUnit.Case
  @moduletag :capture_log

  setup do
    # Start RateLimiter with a limit of 3 requests in 200ms
    start_supervised!({RateLimiter, max_requests: 3, interval: 200})
    :ok
  end

  test "allows requests under the limit" do
    assert {:ok, 1} = RateLimiter.request("192.168.1.1")
    assert {:ok, 2} = RateLimiter.request("192.168.1.1")
    assert {:ok, 3} = RateLimiter.request("192.168.1.1")
  end

  test "blocks request when exceeding the limit" do
    assert {:ok, 1} = RateLimiter.request("192.168.1.2")
    assert {:ok, 2} = RateLimiter.request("192.168.1.2")
    assert {:ok, 3} = RateLimiter.request("192.168.1.2")

    # The 4th request must be blocked
    assert {:error, :rate_limited} = RateLimiter.request("192.168.1.2")
  end

  test "different IPs do not affect each other's limits" do
    assert {:ok, 1} = RateLimiter.request("192.168.1.3")
    assert {:ok, 1} = RateLimiter.request("10.0.0.1")
  end

  test "automatically resets limits after the interval duration" do
    assert {:ok, 1} = RateLimiter.request("192.168.1.4")
    assert {:ok, 2} = RateLimiter.request("192.168.1.4")
    assert {:ok, 3} = RateLimiter.request("192.168.1.4")
    assert {:error, :rate_limited} = RateLimiter.request("192.168.1.4")

    # Wait 250ms (interval is 200ms) for the counter to be reset
    Process.sleep(250)

    # Successfully send again after reset
    assert {:ok, 1} = RateLimiter.request("192.168.1.4")
  end
end
