import 'package:flutter/services.dart';

/// A [TextInputFormatter] that REJECTS just the bad keystroke when an
/// edit doesn't match [pattern], instead of
/// [FilteringTextInputFormatter.allow]'s behavior of stripping
/// disallowed characters out of the new value — which, for an
/// anchored whole-string pattern like `^\d*\.?\d{0,2}$`, wipes the
/// ENTIRE field the moment one keystroke takes it out of shape (e.g.
/// typing a third decimal digit on "1.23" clears the box back to ""
/// instead of just rejecting that one keystroke).
///
/// Final whole-branch review (input-hardening), finding #5.
class RejectingRegexInputFormatter extends TextInputFormatter {
  final RegExp pattern;

  const RejectingRegexInputFormatter(this.pattern);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty || pattern.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}

/// Shared currency input formatters for the price/item-value fields
/// (merchant O2O order price, customer Direct-Delivery item value).
/// Both screens use these instead of each keeping its own inline,
/// duplicated `RegExp` pair.
///
/// NOTE: these only constrain the SHAPE of the input (digits, at most
/// one decimal point, at most 2 decimal places for USD) — they do NOT
/// bound its LENGTH. A plain, correctly-shaped 500-digit string
/// matches `^\d*\.?\d{0,2}$` just fine (`\d*` is unbounded), and
/// `double.tryParse` on a number that long returns `Infinity`, not
/// null — the actual defense against that is `maxLength` on the
/// `AppInput` field itself (see the price fields in
/// merchant_dashboard_screen.dart / customer_dashboard_screen.dart,
/// and the truncation proof in app_input_test.dart), not this
/// formatter.
class CurrencyInputFormatter {
  CurrencyInputFormatter._();

  /// USD: digits, optionally followed by a decimal point and up to
  /// 2 more digits.
  static TextInputFormatter usd() => RejectingRegexInputFormatter(_usdPattern);

  /// LBP: whole numbers only — no decimal point (LBP has no cents).
  static TextInputFormatter lbp() => RejectingRegexInputFormatter(_lbpPattern);

  static final RegExp _usdPattern = RegExp(r'^\d*\.?\d{0,2}$');
  static final RegExp _lbpPattern = RegExp(r'^\d*$');
}
