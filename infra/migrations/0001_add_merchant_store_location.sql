-- Adds merchant store-location columns used by OrderService /
-- PricingService to compute real distance-based delivery fees
-- instead of always falling back to the flat minimum fee.
--
-- application.properties (dev) has spring.jpa.hibernate.ddl-auto=update,
-- so Hibernate adds these columns automatically on local dev. Prod runs
-- ddl-auto=validate (deliberately, see application-prod.properties),
-- so this file must be applied by hand on the VPS before deploying the
-- backend build that references these columns:
--
--   docker exec -i faster_postgres psql -U <db-user> -d <db-name> \
--       < infra/migrations/0001_add_merchant_store_location.sql
--
-- Safe to run multiple times (IF NOT EXISTS). Existing merchants end up
-- with NULL coordinates, which is the intended "not set yet" state —
-- PricingService.calculateDeliveryFee() already falls back to the flat
-- minimum fee when pickup coordinates are null.

ALTER TABLE users ADD COLUMN IF NOT EXISTS store_latitude  DOUBLE PRECISION;
ALTER TABLE users ADD COLUMN IF NOT EXISTS store_longitude DOUBLE PRECISION;
ALTER TABLE users ADD COLUMN IF NOT EXISTS store_address   VARCHAR(255);
