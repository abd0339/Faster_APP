-- Full-codebase review fix round (2026-11) — OrderItemLine entity.
-- Stock decremented at order creation (createOrder/PricingService
-- .decrementStockForOrder) had no persisted record of which items/
-- quantities a given LOGISTICS store order actually contained, so a
-- later cancellation or admin dispute-resolution had no way to give
-- that stock back (PricingService.restoreStockForOrder reads this
-- table). O2O/Direct-Delivery/MOBILITY orders have no catalog items
-- at all, so they never write rows here.
--
-- application.properties (dev) has spring.jpa.hibernate.ddl-auto=update,
-- so Hibernate creates this table automatically on local dev. Prod runs
-- ddl-auto=validate, so this file must be applied by hand on the VPS
-- before deploying the backend build that references this table:
--
--   docker exec -i faster_postgres psql -U <db-user> -d <db-name> \
--       < infra/migrations/0006_add_order_item_lines.sql
--
-- Safe to run multiple times (IF NOT EXISTS).

CREATE TABLE IF NOT EXISTS order_item_lines (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    item_id BIGINT NOT NULL,
    quantity INTEGER NOT NULL,
    created_at TIMESTAMP(6) WITHOUT TIME ZONE
);

CREATE INDEX IF NOT EXISTS idx_order_item_line_order
    ON order_item_lines (order_id);
