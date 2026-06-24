# 💡 Exercise Explanation: Rate Limiter (`GenServer` & `Timer`)

## 1. Practical Requirements & Design
A Rate Limiter is a mandatory component in public Web applications/APIs to prevent DDoS attacks, protect system resources from exhaustion, or limit the usage of specific account plans (API Quota).

**Design requirements:**
*   A centralized GenServer manages the request count of each IP.
*   If the request count of an IP exceeds `max_requests` within `interval` milliseconds, block subsequent requests from that IP.
*   Automatically clear (reset) the counter for each IP when the `interval` expires to prevent RAM usage from growing indefinitely due to storing stale IP data.

---

## 2. Implementation Code Explanation

```elixir
defmodule RateLimiter do
  use GenServer

  # ... Client API ...

  @impl true
  def handle_call({:request, ip}, _from, state) do
    # 1. Get the current request count of the IP in the state.ips map (default is 0)
    current_count = Map.get(state.ips, ip, 0)

    if current_count >= state.max_requests do
      # 2. Limit exceeded -> Reject the request, keep the state unchanged
      {:reply, {:error, :rate_limited}, state}
    else
      new_count = current_count + 1
      new_ips = Map.put(state.ips, ip, new_count)

      # 3. Reset Timer Technique:
      # If this is the first request from this IP in the current cycle (count == 0)
      if current_count == 0 do
        # Register a timer to asynchronously send a :reset_ip message to itself after `state.interval` ms
        :erlang.send_after(state.interval, self(), {:reset_ip, ip})
      end

      {:reply, {:ok, new_count}, %{state | ips: new_ips}}
    end
  end

  @impl true
  def handle_info({:reset_ip, ip}, state) do
    # 4. When the timer triggers -> Delete the IP from the counter map to free up RAM
    new_ips = Map.delete(state.ips, ip)
    {:noreply, %{state | ips: new_ips}}
  end
end
```

---

## 3. Key Points from a Technical Perspective

### 3.1. Why use `:erlang.send_after/3` instead of `Process.sleep/1`?
*   `Process.sleep/1` completely blocks the current process. If you sleep for 5 seconds inside the GenServer, it will hang and be unable to handle any other requests from different IPs, bringing down the entire API system.
*   `:erlang.send_after/3` is a **non-blocking** mechanism. It registers a timer event directly with the Erlang Run-time System (ERTS). ERTS will automatically push a `{:reset_ip, ip}` message into the GenServer's mailbox when the timer expires, while the GenServer continues to receive other requests normally.

### 3.2. Saving Memory (Memory Overhead)
*   If we do not remove IPs from the `state.ips` map when the cycle ends, after a few days of operation with millions of guest client IPs, this Map will bloat to gigabytes of RAM.
*   Calling `Map.delete(state.ips, ip)` when the cycle expires ensures that the GenServer's memory is released in a timely manner, only storing information for IPs that have been actively requesting within the last few seconds.

### 3.3. Limitations of the Fixed Window Solution
*   The solution above applies the **Fixed Window** algorithm: it resets the counter exactly $T$ milliseconds after the first request.
*   *Failure Mode:* If the limit is 100 requests/minute, a user could send 100 requests at second 59, and another 100 requests at second 61 (right after the reset). Consequently, the user has sent 200 requests within just 2 seconds without being blocked.
*   *More Senior Solution:* Use a **Token Bucket** or **Leaky Bucket** algorithm (utilizing Redis sorted sets or libraries like `ExRated` / `Hammer` in a real-world distributed environment).
