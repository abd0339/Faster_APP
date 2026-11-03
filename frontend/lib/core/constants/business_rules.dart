// Shared business-rule constants used across the frontend.
// ────────────────────────────────────────────────────────

/// Maximum straight-line (haversine) pickup→delivery distance, in
/// kilometers, that the app will let a customer/merchant submit
/// without a client-side warning.
///
/// This is a UX-only pre-check — it exists purely to give fast
/// feedback (no network round trip) before the user ever taps
/// submit. The real, authoritative limit lives server-side in
/// `PricingService.exceedsMaxDeliveryDistance` / the
/// `delivery.max-distance-km` Spring property (default 6.0,
/// see application.yml) and is enforced by OrderService on order
/// creation and location updates (input-hardening Tasks 3/5/6).
///
/// MUST be kept in sync with that backend default. If they ever
/// drift, the backend still wins — a value that passes this
/// client-side check but exceeds the server's configured cap will
/// still be rejected by the API; this constant only controls how
/// early the user finds out.
const double kMaxDeliveryDistanceKm = 6.0;
