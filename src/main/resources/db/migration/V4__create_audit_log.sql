CREATE TABLE audit_log (
                           id             UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
                           account_id     UUID           NOT NULL,
                           event_type     VARCHAR(50)    NOT NULL,
                           actor          VARCHAR(255)   NOT NULL,
                           amount         NUMERIC(19, 4),
                           balance_before NUMERIC(19, 4),
                           balance_after  NUMERIC(19, 4),
                           ip_address     VARCHAR(45),
                           metadata       JSONB,
                           created_at     TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

-- Audit queries are always by account, ordered by time
CREATE INDEX idx_audit_log_account_created
    ON audit_log(account_id, created_at DESC);