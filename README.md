# 💳 Fintech Wallet API

A production-grade digital wallet backend built with **event sourcing**, **idempotent transactions**, **Saga-based transfers**, and a **reconciliation engine** — designed to reflect the patterns used in real fintech systems.

> Built as a portfolio project targeting senior backend roles at fintech companies (Capital One, Earnin, etc.)

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        API Gateway (AWS)                         │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS
┌───────────────────────────▼─────────────────────────────────────┐
│                  Spring Boot 4 API (EC2 t2.micro)                │
│                                                                   │
│   ┌─────────────┐   ┌──────────────┐   ┌─────────────────────┐  │
│   │  Account    │   │ Transaction  │   │  Reconciliation Job  │  │
│   │  Controller │   │  Controller  │   │  (Spring Batch)      │  │
│   └──────┬──────┘   └──────┬───────┘   └──────────┬──────────┘  │
│          │                 │                       │              │
│   ┌──────▼─────────────────▼───────────────────────▼──────────┐  │
│   │                    Service Layer                            │  │
│   │   • Idempotency check (DynamoDB)                           │  │
│   │   • Pessimistic locking (SELECT FOR UPDATE)                │  │
│   │   • Saga orchestration (compensating transactions)         │  │
│   └──────────────────────────┬─────────────────────────────────┘  │
│                              │                                    │
│   ┌──────────────────────────▼─────────────────────────────────┐  │
│   │              PostgreSQL — RDS db.t3.micro                   │  │
│   │   • accounts table                                          │  │
│   │   • ledger_events table (append-only, immutable)           │  │
│   │   • audit_log table                                         │  │
│   └─────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│              DynamoDB (always-free tier)                          │
│   • Idempotency key store (TTL: 24h auto-expiry)                 │
│   • Rate limiting token buckets per user                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔑 Key Design Decisions

### Event Sourcing for Balances
Account balances are **never stored directly**. Instead, every transaction appends an immutable event to `ledger_events`, and the balance is derived by summing events per account.

```
balance = SUM(amount) FROM ledger_events WHERE account_id = ?
```

**Why:** Gives you auditability, replay-ability, and trivial rollback — you can reconstruct any account's state at any point in time. At portfolio scale, PostgreSQL handles this fast with a composite index on `(account_id, created_at)`. At production scale, an ElastiCache write-through cache would sit in front.

### Idempotency via DynamoDB
Every mutating endpoint requires an `Idempotency-Key` header. The key + response are stored in DynamoDB with a 24h TTL attribute — items auto-expire with no cleanup job needed.

```
POST /transactions/deposit
Header: Idempotency-Key: a8f3d2e1-...

# Duplicate request with same key → returns stored response, no double-credit
```

**Why:** Network retries and duplicate clicks are a reality in financial systems. Without idempotency, a user who taps "withdraw" twice on a slow connection gets charged twice.

### Saga Pattern for Transfers
Transfers are implemented as a two-step Saga:

```
Step 1: Debit source account
Step 2: Credit destination account
         └── if this throws → compensating transaction re-credits source
```

**Why:** Distributed transactions (2PC) are fragile and slow. The Saga pattern gives you failure recovery without locking two accounts simultaneously.

### Pessimistic Locking for Withdrawals
Concurrent withdrawal requests use `SELECT FOR UPDATE` on the account row to prevent race conditions that could allow overdrafts.

**Why:** Without locking, two simultaneous $60 withdrawals on a $100 balance can both pass the balance check before either commits — resulting in a -$20 balance.

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Language | Java 25 |
| Framework | Spring Boot 4.0.3 |
| Database | PostgreSQL 16 (RDS db.t3.micro) |
| Idempotency / Rate Limiting | AWS DynamoDB (always-free tier) |
| Schema Migrations | Flyway |
| Security | Spring Security + JWT |
| Resilience | resilience4j (circuit breaker) |
| Testing | JUnit 5, Testcontainers |
| Container runtime | Podman |
| Cloud | AWS (EC2, RDS, DynamoDB, API Gateway, CloudWatch) |
| CI/CD | GitHub Actions |

---

## 📡 API Reference

### Accounts

```http
POST /api/v1/accounts
Authorization: Bearer <token>
Content-Type: application/json

{
  "ownerName": "Miguel Arévalo",
  "currency": "USD"
}
```

```http
GET /api/v1/accounts/{accountId}/balance
Authorization: Bearer <token>
```

```http
GET /api/v1/accounts/{accountId}/history?cursor=<cursor>&limit=20
Authorization: Bearer <token>
```

### Transactions

```http
POST /api/v1/transactions/deposit
Authorization: Bearer <token>
Idempotency-Key: <uuid>
Content-Type: application/json

{
  "accountId": "acc_123",
  "amount": 100.00,
  "currency": "USD",
  "description": "Initial deposit"
}
```

```http
POST /api/v1/transactions/withdraw
Authorization: Bearer <token>
Idempotency-Key: <uuid>
Content-Type: application/json

{
  "accountId": "acc_123",
  "amount": 50.00,
  "currency": "USD",
  "description": "ATM withdrawal"
}
```

```http
POST /api/v1/transactions/transfer
Authorization: Bearer <token>
Idempotency-Key: <uuid>
Content-Type: application/json

{
  "sourceAccountId": "acc_123",
  "destinationAccountId": "acc_456",
  "amount": 25.00,
  "currency": "USD",
  "description": "Rent payment"
}
```

### Audit

```http
GET /api/v1/audit/accounts/{accountId}
Authorization: Bearer <token>
```

---

## 🚀 Running Locally

### Prerequisites
- Java 25
- Podman
- Maven 3.9+

### 1. Start PostgreSQL

```bash
podman run -d \
  --name wallet_db \
  -e POSTGRES_DB=wallet \
  -e POSTGRES_USER=wallet_user \
  -e POSTGRES_PASSWORD=wallet_pass \
  -p 127.0.0.1:5432:5432 \
  postgres:16
```

### 2. Configure environment

Copy the example env file:
```bash
cp .env.example .env
```

Fill in your values:
```env
DB_URL=jdbc:postgresql://localhost:5432/wallet
DB_USERNAME=wallet_user
DB_PASSWORD=wallet_pass
JWT_SECRET=your-256-bit-secret-here
AWS_REGION=us-east-1
DYNAMODB_IDEMPOTENCY_TABLE=wallet-idempotency-keys
DYNAMODB_RATE_LIMIT_TABLE=wallet-rate-limits
```

### 3. Run the app

```bash
./mvnw spring-boot:run
```

You should see:
```
Flyway Community Edition by Redgate
Successfully applied N migrations to schema "public"
Started WalletApplication in 3.x seconds
```

### 4. Run tests

```bash
./mvnw test
```

---

## 🗄️ Database Schema

```sql
-- Core accounts table
CREATE TABLE accounts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_name  VARCHAR(255) NOT NULL,
    currency    VARCHAR(3)   NOT NULL DEFAULT 'USD',
    status      VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Append-only event ledger — never UPDATE or DELETE
CREATE TABLE ledger_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id  UUID          NOT NULL REFERENCES accounts(id),
    event_type  VARCHAR(20)   NOT NULL, -- DEPOSIT, WITHDRAWAL, TRANSFER_DEBIT, TRANSFER_CREDIT
    amount      NUMERIC(19,4) NOT NULL,
    actor       VARCHAR(255)  NOT NULL,
    description VARCHAR(500),
    metadata    JSONB,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Fast balance derivation
CREATE INDEX idx_ledger_events_account_created
    ON ledger_events(account_id, created_at DESC);

-- Immutable audit log
CREATE TABLE audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id      UUID          NOT NULL,
    event_type      VARCHAR(50)   NOT NULL,
    actor           VARCHAR(255)  NOT NULL,
    amount          NUMERIC(19,4),
    balance_before  NUMERIC(19,4),
    balance_after   NUMERIC(19,4),
    ip_address      VARCHAR(45),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
```

---

## 🧪 Testing Strategy

| Type | What it covers |
|---|---|
| Unit | Balance derivation logic, idempotency key generation, Saga step ordering |
| Integration | Full transaction flows against a real PostgreSQL (Testcontainers) |
| Concurrency | 10 simultaneous withdrawals on a fixed balance — verifies no overdraft |
| Contract | Idempotency — same key twice returns same response with no side effects |

---

## 📊 Observability

- **Structured logging** — JSON logs with `correlation_id` on every request
- **CloudWatch** — error rate, latency P95, transaction volume dashboards
- **Reconciliation job** — runs every hour via EventBridge, compares `SUM(ledger_events)` vs balance derivation query, alerts on any mismatch
- **Health endpoint** — `GET /actuator/health` exposes DB and DynamoDB dependency status

---

## 🔮 What I Would Add at Scale

- **ElastiCache write-through cache** in front of balance derivation queries — at millions of accounts and thousands of reads/second, the PostgreSQL sum query becomes the bottleneck
- **Kafka event streaming** — publish every ledger event to a topic for downstream fraud detection and analytics consumers
- **Read replicas** — route balance reads to a read replica to offload the primary
- **Multi-region active-passive** — RDS Multi-AZ for failover, cross-region replication for disaster recovery

---

## 👤 Author

**Miguel Arévalo** — Senior Backend Software Engineer  
[LinkedIn](https://www.linkedin.com/in/miguel-arevalo99/) · [GitHub](https://github.com/MiguelArevalo1999)