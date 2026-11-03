import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/core/utils/distance_calculator.dart';

void main() {
  test('kilometersBetween matches known distance', () {
    // Beirut (33.8938, 35.5018) to Tripoli (34.4367, 35.8497).
    // NOTE: the task brief's draft of this test said "~85km", but that
    // is the coastal-highway DRIVING distance. The straight-line
    // (haversine) distance this function computes is ~68km — verified
    // independently against the same formula in PricingService.java
    // and against public mapping sources. 85 is the wrong expectation
    // for a haversine test; 68 is correct.
    expect(
        DistanceCalculator.kilometersBetween(
            33.8938, 35.5018, 34.4367, 35.8497),
        closeTo(68, 5));
  });

  // ───────────────────────────────────────────────────────────
  // Mirrors the fail-safe check applied to
  // the server-side twin of this formula
  // (PricingService.exceedsMaxDeliveryDistance): a coordinate that
  // is NaN/infinite must never silently resolve to a usable
  // distance. Before this fix, Dart's haversine port (same as
  // Java's) would produce NaN and every caller's
  // `distance > kMaxDeliveryDistanceKm` comparison would be FALSE
  // (NaN compares false to everything) — one of the two call
  // sites (customer_dashboard_screen.dart) checks `> cap` to
  // block, so a NaN distance would have silently passed the
  // client-side pre-check instead of warning the customer.
  // ───────────────────────────────────────────────────────────
  test('rejects infinite latitude', () {
    expect(
        () => DistanceCalculator.kilometersBetween(
            double.infinity, 35.5, 34.0, 35.8),
        throwsArgumentError);
  });

  test('rejects NaN longitude', () {
    expect(
        () => DistanceCalculator.kilometersBetween(
            33.8, double.nan, 34.0, 35.8),
        throwsArgumentError);
  });

  test('rejects NaN/infinite in any of the four coordinates', () {
    expect(
        () => DistanceCalculator.kilometersBetween(
            33.8, 35.5, double.nan, 35.8),
        throwsArgumentError);
    expect(
        () => DistanceCalculator.kilometersBetween(
            33.8, 35.5, 34.0, double.infinity),
        throwsArgumentError);
  });

  test('never returns a negative distance for finite inputs', () {
    // Haversine is mathematically non-negative for all finite
    // inputs — verified across (0,0), swapped lat/lng, and
    // identical points, not just the "real" Beirut/Tripoli case
    // above.
    expect(DistanceCalculator.kilometersBetween(0, 0, 0, 0), equals(0));
    expect(DistanceCalculator.kilometersBetween(0, 0, 0.01, 0.01),
        greaterThanOrEqualTo(0));
    // Swapped lat/lng (caller passed lng where lat is expected and
    // vice versa) — still just two finite numbers to the formula;
    // must resolve to a non-negative number, never throw or go
    // negative.
    expect(
        DistanceCalculator.kilometersBetween(35.5018, 33.8938, 35.8497, 34.4367),
        greaterThanOrEqualTo(0));
  });

  test('handles the (0,0) origin coordinate without crashing', () {
    final distance = DistanceCalculator.kilometersBetween(0, 0, 1, 1);
    expect(distance.isFinite, isTrue);
    expect(distance, greaterThan(0));
  });

  test('identical pickup and delivery coordinates give zero distance', () {
    expect(
        DistanceCalculator.kilometersBetween(33.8938, 35.5018, 33.8938, 35.5018),
        equals(0));
  });
}
