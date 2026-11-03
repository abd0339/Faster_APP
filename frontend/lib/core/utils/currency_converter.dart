/// CurrencyConverter — pure LBP/USD conversion helpers.
/// ────────────────────────────────────────────────────
/// No I/O, no state — just the arithmetic, kept in one place
/// so every screen that shows both currencies converts the
/// same way. The exchange rate itself comes from
/// [ExchangeRateService]; callers pass it in here.
class CurrencyConverter {
  CurrencyConverter._();

  /// Converts an LBP amount to USD using [rate] (LBP per 1 USD).
  /// Throws [ArgumentError] if [rate] is not positive, or if [rate]
  /// or [lbp] is NaN/infinite.
  static double lbpToUsd(double lbp, double rate) {
    _checkRate(rate);
    _checkFinite(lbp, 'lbp');
    return lbp / rate;
  }

  /// Converts a USD amount to LBP using [rate] (LBP per 1 USD).
  /// Throws [ArgumentError] if [rate] is not positive, or if [rate]
  /// or [usd] is NaN/infinite.
  static double usdToLbp(double usd, double rate) {
    _checkRate(rate);
    _checkFinite(usd, 'usd');
    return usd * rate;
  }

  // `rate <= 0` alone lets a NaN rate through silently —
  // comparisons against NaN are always false in IEEE 754, so
  // `double.nan <= 0` is false, not true. A NaN or infinite
  // rate/amount would otherwise flow through to a NaN/Infinity
  // result instead of a loud, immediate failure.
  static void _checkRate(double rate) {
    if (!rate.isFinite || rate <= 0) {
      throw ArgumentError.value(rate, 'rate', 'must be a positive, finite number');
    }
  }

  static void _checkFinite(double value, String name) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, name, 'must be a finite number');
    }
  }
}
