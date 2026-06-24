# 🗺️ Practice Guide: System Design (System Design Cookbook)

For Senior Engineer positions, the System Design round does not test whether you remember code syntax, but rather tests your ability to **see the big picture (bird's-eye view)**, perform **back-of-the-envelope estimation**, and make logical **trade-offs**.

This document provides a standard framework to answer and practical system design scenarios.

---

## 1. The 4-Step Framework to Answer Any System Design Question

When receiving a prompt (e.g., *"Design Uber"* or *"Design a Chat System"*), absolutely do not jump straight into drawing diagrams. Follow these 4 steps precisely:

```
+-----------------------------------------------------------------+
| Step 1: Clarifying Requirements                                 |
| - Functional requirements: What can the user do?                |
| - Non-functional requirements: Scale (how many CCUs)? Latency?  |
|   Availability?                                                 |
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| Step 2: High-Level Design                                       |
| - Identify core services (Auth, API Gateway, App Node)          |
| - Main data flow (Client -> LB -> Server -> DB)                 |
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| Step 3: Deep Dive                                               |
| - Choose Database: SQL or NoSQL? Why? What schema?              |
| - Choose Message Broker: Kafka or RabbitMQ?                     |
| - Cache storage: Redis or ETS?                                  |
+-----------------------------------------------------------------+
                               |
                               v
+-----------------------------------------------------------------+
| Step 4: Scale & Bottlenecks                                     |
| - What happens if a node dies? (Failover/Replication)           |
| - Resolve bottlenecks (Thundering herd, Rate limiting)          |
+-----------------------------------------------------------------+
```

---

## 2. Real-World Design Scenario 1: Online Auction System

*   **Requirements:** Allow millions of users to view and place bids on auction items in real-time (Real-time bidding). Bidding history must be absolutely accurate. The highest bid must be updated immediately on the screens of all other users.

### 2.1. Back-of-the-Envelope Estimations
*   **Scale:** 10 million Daily Active Users (DAU).
*   **CCU (Concurrent Users):** Assume at peak time (last minute of the auction) there are 100,000 concurrent users accessing an extremely hot item.
*   **Write rate (Bidding):** 10,000 bids/second.
*   **Read rate (Viewing price):** 100,000 reads/second.

### 2.2. High-Level Design

```
[ Client / Browser ] <--- (WebSocket / Phoenix Channels) ---+
       |                                                    |
   (HTTPS / Bid Request)                                    |
       v                                                    |
  [ API Gateway ]                                           |
       |                                                    |
       v                                                    |
  [ App Service Nodes ] (Elixir Cluster)                    |
       |                                                    |
       +---> [ ETS / Redis Cache ] (Stores current highest bid)|
       |                                                    |
       +---> [ Kafka / Message Queue ]                      |
                   |                                        |
                   v                                        |
             [ Database Worker ]                            |
                   | (Atomic Update DB)                     |
                   v                                        |
             [ PostgreSQL ] (Stores official bid history)   |
```

### 2.3. Trade-offs & Tech Stack Decisions

1.  **WebSocket vs HTTP Polling for displaying new prices:**
    *   *HTTP Polling (Dumb client continuously polling the API every 1s):* Easy to implement, no RAM overhead for maintaining sockets. However, it will crash the server due to excessive HTTP overhead (100k requests/s).
    *   *WebSockets (Phoenix Channels):* Client maintains a single connection. The server pushes updates directly when there is a new price. Elixir manages WebSockets extremely well (100k connections consume only ~200MB RAM). -> **Choice: WebSockets**.
2.  **Handling Race Conditions when bidding (Concurrency Conflict):**
    *   *Problem:* Two users simultaneously place a bid of $100$ USD for an item currently priced at $99$ USD in the exact same millisecond. The system must accept only one user and reject the other.
    *   *Solution 1 (Optimistic Locking in DB):* Use version checks in the Database. If the DB update fails -> return an error to the user. However, this generates thousands of failed writes to the disk-based DB, causing database bottlenecks.
    *   *Solution 2 (GenServer Actor Model):* Each active auction item is managed by a single GenServer in the Cluster (using Registry to find the PID). All bidding requests for this item must go through that GenServer. Since GenServer processes its mailbox sequentially, it will accept the first incoming request, update the in-memory cache, and immediately reject the subsequent request without querying the Database. -> **Choice: Actor Model (GenServer)** as a concurrency gatekeeper at the App layer, then asynchronously write to the DB via a Queue.

---

## 3. Real-World Design Scenario 2: Mass Notification Push System

*   **Requirements:** Send urgent messages (such as promotional info or disaster alerts) to 5 million users within a maximum of 1 minute via App Push Notifications (APNS/FCM) and WebSockets.

### 3.1. Core Issues to Resolve
1.  **Third-Party API Rate Limits (FCM/APNS Rate Limits):** Apple and Google impose limits on the number of push requests sent to their servers per second. If sent too quickly, your account may be blocked or messages delayed.
2.  **Fault Tolerance on Crash:** If the server crashes while sending to the 2nd million, how does the system know to resume from the 3rd million upon restart without duplicates to the first 2 million users?

### 3.2. Detailed Design (Deep Dive)
*   **Broadway & GenStage to manage Backpressure:**
    *   Store the list of 5 million target users in a Message Broker (like Kafka).
    *   Use Elixir Broadway as the Consumer. Broadway will adjust the `max_demand` configuration to precisely control the reading rate from Kafka, matching the rate limits of the Google/Apple APIs.
*   **Stateful Tracking:**
    *   Do not send raw fire-and-forget messages. Each message delivery job is assigned a `UUID`.
    *   Use a fast KV Store (like Redis or Postgres with Index) to track the state of each `UUID` (`pending`, `processing`, `sent`, `failed`).
    *   Once a worker successfully sends a message, update the status to `sent`. If a worker crashes midway, upon restart, the system only needs to query the `UUID`s with `pending` status in the Kafka partition to continue processing.

---

## 💡 System Design Practice Guide

1.  **Practice drawing Architectural Diagrams:** Practice sketching system design diagrams on paper or online tools (Excalidraw/draw.io). Focus on clearly showing: Where the App Nodes, Cache, Database are, and the direction of the data flows.
2.  **Practice answering the "Why?" questions:** Do not just say *"I choose PostgreSQL"*. Say *"I choose PostgreSQL because we need to ensure high ACID compliance for transaction history, and the data does not require continuous schema changes like NoSQL"*.
