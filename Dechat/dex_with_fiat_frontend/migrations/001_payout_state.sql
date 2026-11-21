-- Migration 001: Payout state and transitions schema (Issue #97)

CREATE TABLE IF NOT EXISTS payout_intents (
  id VARCHAR(64) PRIMARY KEY,
  idempotency_key VARCHAR(128) UNIQUE NOT NULL,
  contract_tx_hash VARCHAR(64) NOT NULL,
  status VARCHAR(32) NOT NULL,
  amount_minor_units BIGINT NOT NULL,
  currency VARCHAR(8) NOT NULL,
  provider_reference VARCHAR(128) UNIQUE,
  recipient_account_masked VARCHAR(32) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS payout_state_transitions (
  id BIGSERIAL PRIMARY KEY,
  payout_id VARCHAR(64) REFERENCES payout_intents(id) ON DELETE CASCADE,
  from_status VARCHAR(32) NOT NULL,
  to_status VARCHAR(32) NOT NULL,
  reason TEXT,
  transitioned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_payout_intents_status ON payout_intents(status);
CREATE INDEX IF NOT EXISTS idx_payout_intents_created_at ON payout_intents(created_at);

-- Issue #217: Tenant-aware AI budget accounting with atomic reservations.
-- Reservations are taken before model dispatch against both a per-user and a
-- global spend ceiling; actual usage is reconciled afterward. The reserved
-- amount is held in `reserved_minor_units` until the request settles, at which
-- point it is released and `spent_minor_units` is incremented by the actual
-- cost. Concurrent requests are serialized per tenant/user via row locks so
-- that the sum of reserved + spent can never exceed the configured ceiling.

CREATE TABLE IF NOT EXISTS ai_budget_accounts (
  tenant_id VARCHAR(64) NOT NULL,
  user_id VARCHAR(64) NOT NULL,
  currency VARCHAR(8) NOT NULL DEFAULT 'USD',
  -- Configured ceilings (NULL means unlimited for that scope).
  user_ceiling_minor_units BIGINT,
  global_ceiling_minor_units BIGINT,
  -- Running totals for this tenant/user scope.
  reserved_minor_units BIGINT NOT NULL DEFAULT 0,
  spent_minor_units BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (tenant_id, user_id),
  CONSTRAINT ai_budget_accounts_non_negative
    CHECK (reserved_minor_units >= 0 AND spent_minor_units >= 0)
);

-- One row per tenant to enforce the global ceiling atomically across users.
CREATE TABLE IF NOT EXISTS ai_budget_tenant_totals (
  tenant_id VARCHAR(64) PRIMARY KEY,
  currency VARCHAR(8) NOT NULL DEFAULT 'USD',
  global_ceiling_minor_units BIGINT,
  reserved_minor_units BIGINT NOT NULL DEFAULT 0,
  spent_minor_units BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ai_budget_tenant_totals_non_negative
    CHECK (reserved_minor_units >= 0 AND spent_minor_units >= 0)
);

-- Individual reservations. A reservation is created before dispatch and
-- settled (reconciled) or released (rolled back) afterward. The status column
-- makes the lifecycle explicit so partial/error responses can be reconciled.
CREATE TABLE IF NOT EXISTS ai_budget_reservations (
  id VARCHAR(64) PRIMARY KEY,
  tenant_id VARCHAR(64) NOT NULL,
  user_id VARCHAR(64) NOT NULL,
  request_id VARCHAR(128),
  status VARCHAR(32) NOT NULL DEFAULT 'reserved',
  reserved_minor_units BIGINT NOT NULL,
  actual_minor_units BIGINT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  settled_at TIMESTAMP WITH TIME ZONE,
  CONSTRAINT ai_budget_reservations_status_check
    CHECK (status IN ('reserved', 'settled', 'released')),
  CONSTRAINT ai_budget_reservations_amounts_check
    CHECK (reserved_minor_units >= 0 AND (actual_minor_units IS NULL OR actual_minor_units >= 0))
);

CREATE INDEX IF NOT EXISTS idx_ai_budget_reservations_scope
  ON ai_budget_reservations(tenant_id, user_id, status);
CREATE INDEX IF NOT EXISTS idx_ai_budget_reservations_request
  ON ai_budget_reservations(request_id);
