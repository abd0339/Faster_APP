import 'dart:math';

/// DistanceCalculator — pure great-circle distance helper.
/// ────────────────────────────────────────────────────────
/// No I/O, no state — a Dart port of the same haversine formula
/// used server-side in `PricingService.haversineKm` (Earth radius
/// 6371 km), so the frontend can warn before ever calling the API.
/// Kept purely functional, like [CurrencyConverter], so every
/// screen that needs a quick distance check computes it the same
/// way.
class DistanceCalculator {
  DistanceCalculator._();

  static const double _earthRadiusKm = 6371.0;

  /// Great-circle distance between (lat1, lng1) and (lat2, lng2),
  /// in kilometers. Throws [ArgumentError] if any coordinate is
  /// NaN or infinite.
  ///
  /// Mirrors the same fail-safe check applied to the server-side
  /// twin of this formula (PricingService.exceedsMaxDeliveryDistance):
  /// without this
  /// check, a non-finite coordinate makes sin()/cos() of an
  /// infinite radian value produce NaN, and `distance >
  /// kMaxDeliveryDistanceKm` is FALSE for NaN — silently defeating
  /// the client-side pre-check instead of warning the user.
  static double kilometersBetween(
      double lat1, double lng1, double lat2, double lng2) {
    for (final entry in {
      'lat1': lat1,
      'lng1': lng1,
      'lat2': lat2,
      'lng2': lng2,
    }.entries) {
      if (!entry.value.isFinite) {
        throw ArgumentError.value(
            entry.value, entry.key, 'must be a finite coordinate');
      }
    }

    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return _earthRadiusKm * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}
