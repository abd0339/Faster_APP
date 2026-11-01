-- Defense-in-depth for the LedgerService.recordDriverCommission race
-- found in code review (2026-11-01). The application-level guard
-- (existsByOrderIdAndCategory, now checked while holding a pessimistic
-- lock on the driver's row) should already prevent double-recording,
-- but a DB constraint is what actually guarantees it regardless of
-- future code changes.
--
-- Scoped to DRIVER_COMMISSION only (a partial index, which JPA
-- @UniqueConstraint cannot express) because other categories —
-- REFUND, ADJUSTMENT — may legitimately have more than one entry
-- against the same order (e.g. a partial refund followed by another).
-- DRIVER_COMMISSION is the only category with an existing
-- "don't record twice for this order" invariant.
--
-- Run on both local dev (ddl-auto=update does NOT create partial
-- indexes) and prod (ddl-auto=validate, always requires manual
-- migrations — see 0001/0002 in this folder):
--
--   docker exec -i faster_postgres psql -U <db-user> -d <db-name> \
--       < infra/migrations/0003_unique_driver_commission_per_order.sql
--
-- Safe to run multiple times (IF NOT EXISTS).

CREATE UNIQUE INDEX IF NOT EXISTS uq_ledger_driver_commission_per_order
ON ledger_entries (order_id)
WHERE category = 'DRIVER_COMMISSION';
