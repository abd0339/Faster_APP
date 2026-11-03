-- input-hardening plan (Task 4) — orders whose delivery distance exceeds
-- the configured cap (PricingService.exceedsMaxDeliveryDistance, Task 3)
-- now get flagged for admin review instead of being silently accepted.
-- See Order.isDistanceFlagged.
--
-- application.properties (dev) has spring.jpa.hibernate.ddl-auto=update,
-- so Hibernate adds these columns automatically on local dev. Prod runs
-- ddl-auto=validate, so this file must be applied by hand on the VPS
-- before deploying the backend build that references these columns:
--
--   docker exec -i faster_postgres psql -U <db-user> -d <db-name> \
--       < infra/migrations/0005_add_order_distance_flag.sql
--
-- Safe to run multiple times (IF NOT EXISTS).

ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_distance_flagged BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS distance_flag_reason VARCHAR(255);
