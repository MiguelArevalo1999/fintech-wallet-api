# ADR-001: Event Sourcing for Balance Management

## Status
Accepted

## Context
We need to store account balances. The simplest approach is a `balance`
column on the accounts table, updated on every transaction.

## Decision
We use an append-only `ledger_events` table. Balances are derived
by summing events per account. We also store a `running_balance`
denormalization on each event for efficient statement queries.

## Consequences

**Positive:**
- Full audit trail — every balance state is reconstructable
- Trivial rollback — replay events up to any point in time
- No UPDATE contention on a balance column under high write load

**Negative:**
- Balance derivation requires a SUM query (mitigated by index and
  running_balance column)
- More complex write path — running_balance must be computed at
  write time
- Schema migrations affecting ledger_events are riskier

## Alternatives Considered
- **Balance column:** Simpler reads, but loses history and creates
  UPDATE contention under concurrent writes
- **CQRS with separate read model:** More scalable but significantly
  more complex — overkill at this stage