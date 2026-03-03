CREATE TABLE ledger_events (
                               id              UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
                               account_id      UUID           NOT NULL REFERENCES accounts(id),
                               event_type      VARCHAR(30)    NOT NULL,
                               amount          NUMERIC(19, 4) NOT NULL,
                               running_balance NUMERIC(19, 4) NOT NULL,
                               actor           VARCHAR(255)   NOT NULL,
                               description     VARCHAR(500),
                               metadata        JSONB,
                               idempotency_key VARCHAR(255)   UNIQUE,
                               created_at      TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

                               CONSTRAINT chk_event_type CHECK (
                                   event_type IN (
                                                  'DEPOSIT',
                                                  'WITHDRAWAL',
                                                  'TRANSFER_DEBIT',
                                                  'TRANSFER_CREDIT',
                                                  'REVERSAL'
                                       )
                                   ),
                               CONSTRAINT chk_amount_not_zero CHECK (amount != 0)
    );

-- This is the most important index in the whole project.
-- Every balance derivation query hits this.
CREATE INDEX idx_ledger_events_account_created
    ON ledger_events(account_id, created_at DESC);

-- Prevents duplicate events from the same idempotency key
CREATE UNIQUE INDEX idx_ledger_events_idempotency
    ON ledger_events(idempotency_key)
    WHERE idempotency_key IS NOT NULL;