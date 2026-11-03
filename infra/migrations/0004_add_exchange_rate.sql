-- Adds the single-row exchange_rate table backing the
-- admin-settable USD/LBP exchange rate feature.
--
-- Singleton row: id is always 1 (enforced in application code,
-- never auto-generated). ExchangeRateService.getCurrentRate()
-- reads this row and throws NotFoundException if it's missing,
-- which should only happen if this migration wasn't run.
--
-- Run on both local dev (ddl-auto=update does NOT insert seed
-- data) and prod (ddl-auto=validate, always requires manual
-- migrations — see 0001/0002/0003 in this folder):
--
--   docker exec -i faster_postgres psql -U <db-user> -d <db-name> \
--       < infra/migrations/0004_add_exchange_rate.sql
--
-- Safe to run multiple times (IF NOT EXISTS / ON CONFLICT DO NOTHING).

CREATE TABLE IF NOT EXISTS exchange_rate (
    id BIGINT PRIMARY KEY,
    usd_to_lbp_rate NUMERIC(14,2) NOT NULL,
    updated_at TIMESTAMP,
    updated_by_admin_id BIGINT
);

INSERT INTO exchange_rate (id, usd_to_lbp_rate, updated_at)
VALUES (1, 89500.00, now())
ON CONFLICT (id) DO NOTHING;
