# 🎯 Structured Curriculum - Senior Elixir Interview Roadmap

This directory contains comprehensive theoretical resources, real-world interview questions, supplementary cookbooks, and coding exercises to guide your preparation for a Senior Elixir interview.

---

## 📅 Curriculum Sections

### **Section 1: Core OTP, Database (Ecto/Postgres) & Coding**
*   **Theory (Conceptual):** Detailed guide at [otp_database_prep.md](otp_database_prep.md). Focuses on BEAM VM scheduling & memory internals, tail-recursive GenServer mailbox mechanics, and Ecto optimizations.
*   **Practice (Coding):** Features 5 practical exercises separated into individual directories:
    1.  **Ledger Transaction:** Secure financial ledger transactions using `Ecto.Multi` and sandbox isolation.
        *   Directory: [exercises/01_ledger](exercises/01_ledger)
        *   Source Code: [ledger_practice.exs](exercises/01_ledger/ledger_practice.exs)
        *   Explanation Guide: [ledger_explain.md](exercises/01_ledger/ledger_explain.md)
    2.  **Session Manager:** Dynamic process supervision using `DynamicSupervisor` and naming registration with `Registry`.
        *   Directory: [exercises/02_session_manager](exercises/02_session_manager)
        *   Source Code: [session_manager_practice.exs](exercises/02_session_manager/session_manager_practice.exs)
        *   Explanation Guide: [session_manager_explain.md](exercises/02_session_manager/session_manager_explain.md)
    3.  **Job Queue (Advanced):** Orchestrating asynchronous tasks with concurrency limits (`max_concurrency`) using `Task.Supervisor` and process monitoring (`monitor`).
        *   Directory: [exercises/03_job_queue](exercises/03_job_queue)
        *   Source Code: [job_queue_practice.exs](exercises/03_job_queue/job_queue_practice.exs)
        *   Explanation Guide: [job_queue_explain.md](exercises/03_job_queue/job_queue_explain.md)
    4.  **Write-Through Cache (Advanced):** Designing an ultra-fast read-optimized cache utilizing concurrent ETS reads while ensuring synchronous write safety via a GenServer and DB back-end.
        *   Directory: [exercises/04_write_through_cache](exercises/04_write_through_cache)
        *   Source Code: [write_through_cache_practice.exs](exercises/04_write_through_cache/write_through_cache_practice.exs)
        *   Explanation Guide: [write_through_cache_explain.md](exercises/04_write_through_cache/write_through_cache_explain.md)
    5.  **Data Structures & Algorithms:** A compilation of classic algorithms solved using Elixir functional patterns (Word Reversal, Anagram Grouping, Bracket Validation using Stack).
        *   Directory: [exercises/07_algorithms](exercises/07_algorithms)
        *   Source Code: [algorithm_practice.exs](exercises/07_algorithms/algorithm_practice.exs)
        *   Algorithm Tricks Cookbook: [algorithm_tricks.md](exercises/07_algorithms/algorithm_tricks.md)
*   **Review:** Self-assess with the quick-response question guide for this section.

### **Section 2: Distributed Systems, Message Brokers, DevOps & System Design**
*   **Theory & Architecture:** Detailed guide at [distributed_devops_prep.md](distributed_devops_prep.md). Focuses on clustering, message brokers (Kafka vs. RabbitMQ), observability (:telemetry, Prometheus), and DevOps practices.
*   **Practice (Coding):** Features 2 concurrency & rate-limiting exercises:
    1.  **Rate Limiter:** A GenServer to manage request frequencies per IP with a reset timer.
        *   Directory: [exercises/05_rate_limiter](exercises/05_rate_limiter)
        *   Source Code: [rate_limiter_practice.exs](exercises/05_rate_limiter/rate_limiter_practice.exs)
        *   Explanation Guide: [rate_limiter_explain.md](exercises/05_rate_limiter/rate_limiter_explain.md)
    2.  **Batch Processor:** Auto-flush data buffering (batching) triggered by batch size or timeout thresholds.
        *   Directory: [exercises/06_batch_processor](exercises/06_batch_processor)
        *   Source Code: [batcher_practice.exs](exercises/06_batch_processor/batcher_practice.exs)
        *   Explanation Guide: [batcher_explain.md](exercises/06_batch_processor/batcher_explain.md)
*   **System Design & Mock Preparation:** Designing a high-concurrency Notification Gateway (100k CCU) and preparing behavioral stories using the STAR method.

---

## 📚 Supplementary Non-Elixir Study Cookbooks

To maximize your performance in comprehensive Senior rounds, proactively review these dedicated guides:

1.  **[System Design Cookbook](system_design_prep.md):** A structured 4-step framework for architectural interviews. Contains scenarios on designing an online auction system resolving race conditions and a mass notification gateway addressing rate-limiting & backpressure.
2.  **[Behavioral & Leadership Cookbook](behavioral_prep.md):** Constructing stories with the STAR method. Scenarios cover resolving technical disagreements within a team and mentoring engineers transitioning to functional programming (FP).
3.  **[DevOps & Observability Cookbook](devops_observability_prep.md):** Writing size-optimized, secure Dockerfiles (<80MB) and configuring Prometheus/Grafana to monitor memory and process metrics in the BEAM VM.

---

## 💻 Running the Live Coding Exercises

These practical exercises are designed as self-contained Elixir script files (`.exs`) with built-in `ExUnit` test suites. You can run them directly from the terminal without creating a full Mix project.

Examples:
```bash
# Section 1 Coding Exercises
elixir exercises/01_ledger/ledger_practice.exs
elixir exercises/02_session_manager/session_manager_practice.exs
elixir exercises/03_job_queue/job_queue_practice.exs
elixir exercises/04_write_through_cache/write_through_cache_practice.exs
elixir exercises/07_algorithms/algorithm_practice.exs

# Section 2 Coding Exercises
elixir exercises/05_rate_limiter/rate_limiter_practice.exs
elixir exercises/06_batch_processor/batcher_practice.exs
```

*Each directory includes complete reference implementations and step-by-step explanations of the underlying mechanisms.*

---

## 💡 Key Tips for Senior Elixir Interviews
*   **Think Out Loud:** During live coding, explain your thought process continuously (e.g., explain why you choose pattern matching over if/else, or why you use `Ecto.Multi` instead of a plain transaction block).
*   **Trade-off Mindset:** When designing systems, explicitly discuss the pros and cons of choices (e.g., Redis vs. ETS, Kafka vs. RabbitMQ). Emphasize that there are no perfect solutions, only solutions tailored to a given context.
*   **STAR Structure:** For situational (behavioral) questions, structure your answers clearly: Situation, Task, Action (what YOU did, specifically), and Result (quantifiable metrics).

---

## 📝 Syntax Cheat Sheet
If you understand the logic but need a quick reference for specific Erlang/Elixir syntax (e.g., via tuples, `:ets`, `:erlang.send_after`), check out our quick reference guide:
*   **[Syntax Cheat Sheet](exercises/syntax_cheat_sheet.md)**
