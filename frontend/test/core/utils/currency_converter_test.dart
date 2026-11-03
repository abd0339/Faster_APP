import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/core/utils/currency_converter.dart';

void main() {
  test('lbpToUsd divides by rate', () {
    expect(CurrencyConverter.lbpToUsd(89500, 89500), closeTo(1.0, 0.001));
  });

  test('usdToLbp multiplies by rate', () {
    expect(CurrencyConverter.usdToLbp(1.0, 89500), closeTo(89500, 0.01));
  });

  test('rejects non-positive rate', () {
    expect(() => CurrencyConverter.lbpToUsd(100, 0), throwsArgumentError);
  });

  // ───────────────────────────────────────────────────────────
  // Hostile numeric inputs. Realistic UI
  // text parsing (double.tryParse of a digits-only, formatter-
  // constrained field) can't actually produce NaN/Infinity, but
  // these are pure utility functions with no other guard, so a
  // future caller (or a value surviving some other conversion
  // path) could still hand them one. "Garbage in, silent garbage
  // out" is exactly the class of bug this whole plan targets.
  // ───────────────────────────────────────────────────────────
  test('rejects NaN rate', () {
    expect(() => CurrencyConverter.lbpToUsd(100, double.nan),
        throwsArgumentError);
  });

  test('rejects infinite rate', () {
    expect(() => CurrencyConverter.lbpToUsd(100, double.infinity),
        throwsArgumentError);
  });

  test('rejects NaN lbp amount', () {
    expect(() => CurrencyConverter.lbpToUsd(double.nan, 89500),
        throwsArgumentError);
  });

  test('rejects infinite lbp amount', () {
    expect(() => CurrencyConverter.lbpToUsd(double.infinity, 89500),
        throwsArgumentError);
  });

  test('rejects NaN usd amount', () {
    expect(() => CurrencyConverter.usdToLbp(double.nan, 89500),
        throwsArgumentError);
  });

  test('rejects infinite usd amount', () {
    expect(() => CurrencyConverter.usdToLbp(double.infinity, 89500),
        throwsArgumentError);
  });

  test('rejects NaN rate in usdToLbp', () {
    expect(() => CurrencyConverter.usdToLbp(1.0, double.nan),
        throwsArgumentError);
  });

  test('handles very large but finite values without producing infinity',
      () {
    final result = CurrencyConverter.lbpToUsd(1e15, 89500);
    expect(result.isFinite, isTrue);
  });

  test('handles very small but finite positive values', () {
    final result = CurrencyConverter.lbpToUsd(1e-10, 89500);
    expect(result, closeTo(0, 1e-10));
    expect(result.isNegative, isFalse);
  });

  test('zero lbp amount converts to zero, not an error', () {
    expect(CurrencyConverter.lbpToUsd(0, 89500), equals(0));
  });
}
