CREATE TABLE accounts (
                          id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
                          owner_id    VARCHAR(255) NOT NULL,
                          owner_name  VARCHAR(255) NOT NULL,
                          currency    VARCHAR(3)   NOT NULL DEFAULT 'USD',
                          status      VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
                          created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
                          updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),

                          CONSTRAINT chk_currency   CHECK (currency IN ('USD', 'MXN', 'EUR')),
                          CONSTRAINT chk_status     CHECK (status   IN ('ACTIVE', 'SUSPENDED', 'CLOSED'))
);

CREATE INDEX idx_accounts_owner_id ON accounts(owner_id);