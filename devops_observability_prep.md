# 🛠️ Practice Guide: DevOps & System Monitoring (DevOps & Observability Cookbook)

A Senior Elixir Engineer must do more than write clean code locally; they need to understand containerization, deployment, and how to monitor production applications.

This document compiles practical expertise for DevOps and system monitoring in production.

---

## 1. Containerization (Multi-stage Dockerfile for Elixir)

If you present a naive Dockerfile that installs Erlang and Elixir on a single production runtime image during an interview, it will likely be viewed unfavorably for two major reasons:
*   **Large Image Size:** Images exceeding 1GB waste bandwidth during deployments and consume excess storage on Kubernetes nodes.
*   **Security Vulnerabilities:** Retaining compilation tools (`gcc`, `git`, `mix`) inside the running container expands the attack surface if the container is compromised.

### 1.1. Production-Ready Multi-Stage Dockerfile
```dockerfile
# ==============================================================================
# STAGE 1: Build Environment (Compiler & Tools)
# ==============================================================================
FROM elixir:1.15-alpine AS builder

# 1. Install system tools required to compile Erlang Native Implemented Functions (NIFs)
RUN apk add --no-cache build-base git

WORKDIR /app

# 2. Install Hex and Rebar globally
RUN mix local.hex --force && mix local.rebar --force

# 3. Configure production environment
ENV MIX_ENV=prod

# 4. Copy dependency manifests and cache dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# 5. Copy source code, compile application, and assemble the release
COPY . .
RUN mix compile
RUN mix release

# ==============================================================================
# STAGE 2: Runtime Environment (Minimal & Secure)
# ==============================================================================
FROM alpine:3.18

# 6. Install minimal runtime system dependencies (openssl, libstdc++, ncurses-libs)
# Dynamically compiled BEAM VM requires these libraries to execute.
RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app

# 7. Copy only the compiled release artifacts from Stage 1 to Stage 2
# Completely bypasses original source code, compilers, and Git history.
COPY --from=builder /app/_build/prod/rel/my_app ./

# Configure a non-privileged system user (non-root) to enhance container security
RUN adduser -D appuser && chown -R appuser:appuser /app
USER appuser

ENV MIX_ENV=prod

# Start the application using the Mix release boot script
CMD ["/app/bin/my_app", "start"]
```

*   **Why does the final image not require Erlang or Elixir installed in Stage 2?**
    *   The `mix release` command packages all compiled code into `.beam` files along with the ERTS (Erlang Run-Time System, which contains the BEAM VM execution engine). The Stage 2 runtime image is a minimal Alpine Linux layer containing only these binaries, reducing the final image size to approximately **50MB - 80MB**.

---

## 2. System Monitoring (Observability Pipeline)

In production, you cannot securely SSH into servers to run commands like `iex --sname production` or launch the interactive GUI `:observer` due to network isolation and security policies. System telemetry must be funneled to a centralized monitoring pipeline instead.

```
+-----------------------------------------------------------------+
| App Server (Elixir Node)                                        |
|                                                                 |
| [Ecto / Phoenix / Broadway]                                     |
|           | (Dispatches telemetry events)                       |
|           v                                                     |
| [ :telemetry event pipeline ]                                   |
|           | (Telemetry.Metrics listens & transforms)            |
|           v                                                     |
| [ Telemetry.Metrics.Prometheus adapter ]                        |
|           | (Exposes endpoint: /metrics)                        |
+-----------------------------------------------------------------+
                               |
                               | 1. Pulls metrics (e.g., every 15s)
                               v
               +---------------------------------------+
               | Prometheus Server (Time-Series DB)    |
               +---------------------------------------+
                               |
                               | 2. Renders monitoring graphs
                               v
               +---------------------------------------+
               | Grafana Dashboard                     |
               +---------------------------------------+
```

### 2.1. Critical BEAM VM Metrics to Monitor
When building Grafana dashboards for Elixir systems, configure visualization panels and alerting rules for these key metrics:
1.  **Process Count:** The number of active processes. A vertical spike indicates a process leak (e.g., spawning unmonitored `Task` processes or infinite restart loops in crashed GenServers).
2.  **Atom Count:** The current number of loaded atoms. The BEAM VM does not garbage-collect atoms. If the atom count reaches the default limit (1,048,576), the BEAM VM will **immediately crash the entire application**.
    *   *Security Rule:* Never use `String.to_atom/1` on external, untrusted input (such as JSON keys or API request parameters). Use `String.to_existing_atom/1` instead.
3.  **Run Queue Length:** The number of processes waiting for CPU scheduler time. A high count relative to system CPU cores over a sustained period indicates CPU-bound bottlenecks.
4.  **Ecto Connection Pool:** The number of database connections in use. Reaching the maximum threshold (`pool_size`) will cause subsequent HTTP requests to time out while waiting for a database connection.

---

## 💡 Practice Guide for DevOps & Observability
1.  **Write a Dockerfile:** Write a multi-stage Dockerfile from scratch for a blank Elixir application and build it locally to experiment with minimizing image size.
2.  **Read Telemetry Configurations:** Research the `:telemetry` library in Elixir. Examine how metrics like `counter`, `sum`, and `last_value` are declared in the standard Phoenix template file `lib/my_app_web/telemetry.ex`.
3.  **Analyze Centralized Logs:** Familiarize yourself with centralized log management (ELK Stack, Grafana Loki). Practice querying logs using trace IDs to trace single request flows across multiple microservices.
