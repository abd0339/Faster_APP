-- M3 fix — O2O orders keep manual merchant-entered pricing (phone
-- orders can include off-catalog items), but a suspiciously low
-- price now gets flagged for admin review instead of going through
-- silently. See PricingService.validateO2OPrice() / Order.isPriceFlagged.
--
-- application.properties (dev) has spring.jpa.hibernate.ddl-auto=update,
-- so Hibernate adds these columns automatically on local dev. Prod runs
-- ddl-auto=validate, so this file must be applied by hand on the VPS
-- before deploying the backend build that references these columns:
--
--   docker exec -i faster_postgres psql -U <db-user> -d <db-name> \
--       < infra/migrations/0002_add_order_price_flag.sql
--
-- Safe to run multiple times (IF NOT EXISTS).

ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_price_flagged BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS price_flag_reason VARCHAR(255);
