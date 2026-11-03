import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/core/utils/currency_input_formatter.dart';

/// Task 9 wired `FilteringTextInputFormatter.allow(RegExp(...))`
/// directly into merchant_dashboard_screen.dart and
/// customer_dashboard_screen.dart's price/item-value fields, with each
/// screen duplicating the identical two inline patterns. The final
/// whole-branch review (input-hardening) found two problems with that:
///
///  1. `FilteringTextInputFormatter.allow` CLEARS THE WHOLE FIELD the
///     moment one keystroke doesn't match the (anchored, whole-string)
///     pattern — e.g. typing a third decimal digit on "1.23" wipes the
///     box back to "" instead of just rejecting that one keystroke.
///  2. The plan's own "500+ character hostile string rejected by the
///     formatter" requirement was NOT actually met: the pre-existing
///     version of this test only passed because of an incidental
///     ".123" suffix in the test string. A PLAIN 500-digit string (no
///     decimal point) matches `^\d*\.?\d{0,2}$` just fine — `\d*` is
///     unbounded — so it sailed straight through, and
///     `double.tryParse` on a number that long returns `Infinity`, not
///     null. The real defense against that is `maxLength` on the
///     `AppInput` field itself (see app_input_test.dart and the price
///     fields in both screens), not this formatter — this file no
///     longer claims otherwise.
///
/// This now exercises the shared [CurrencyInputFormatter] both screens
/// use instead of each having its own inline `RegExp` (closing the
/// duplication finding too), via a helper that can simulate a REAL
/// multi-keystroke edit (oldValue -> newValue), not just a single paste
/// from empty — needed to actually prove point 1 above.
void main() {
  final usdFormatter = CurrencyInputFormatter.usd();
  final lbpFormatter = CurrencyInputFormatter.lbp();

  String applyEdit(TextInputFormatter f, String oldText, String newText) {
    final oldValue = TextEditingValue(
        text: oldText, selection: TextSelection.collapsed(offset: oldText.length));
    final newValue = TextEditingValue(
        text: newText, selection: TextSelection.collapsed(offset: newText.length));
    return f.formatEditUpdate(oldValue, newValue).text;
  }

  String apply(TextInputFormatter f, String text) => applyEdit(f, '', text);

  group('USD price formatter (^\\d*\\.?\\d{0,2}\$)', () {
    test('accepts a clean decimal value', () {
      expect(apply(usdFormatter, '12.5'), equals('12.5'));
    });

    test('accepts an integer value', () {
      expect(apply(usdFormatter, '1200'), equals('1200'));
    });

    test('rejects Arabic-Indic digits', () {
      expect(apply(usdFormatter, '١٢٣٤٥'), equals(''));
    });

    test('rejects full-width digits', () {
      expect(apply(usdFormatter, '１２３４５'), equals(''));
    });

    test('rejects scientific notation', () {
      expect(apply(usdFormatter, '1e10'), equals(''));
    });

    test('rejects multiple decimal points', () {
      expect(apply(usdFormatter, '1.2.3'), equals(''));
    });

    test('rejects pasted currency-symbol/comma strings', () {
      expect(apply(usdFormatter, '\$1,234.56'), equals(''));
    });

    test('rejects a 500+ character string (contains letters)', () {
      expect(apply(usdFormatter, 'A' * 500 + '1.23'), equals(''));
    });

    test('rejects a 500+ digit string with a 3rd decimal digit', () {
      // Rejected because of the 3-decimals shape violation (.123),
      // NOT because of its length — see the next test, which is the
      // one the final review added because this one alone was
      // misleadingly presented as proving a length defense.
      expect(apply(usdFormatter, '1' * 500 + '.123'), equals(''));
    });

    test(
        'a plain 500-digit string matches the shape pattern — length is '
        'NOT bounded here by design (see app_input_test.dart for the '
        'actual defense: maxLength on the AppInput field)', () {
      final longDigits = '1' * 500;
      expect(apply(usdFormatter, longDigits), equals(longDigits));
    });

    test('rejects emoji', () {
      expect(apply(usdFormatter, '😀123'), equals(''));
    });

    test('rejects an embedded null byte', () {
      expect(apply(usdFormatter, '12\u000034'), equals(''));
    });

    test('rejects a trailing third decimal digit', () {
      expect(apply(usdFormatter, '1.234'), equals(''));
    });

    // Point 1 — the actual formatter bug this review found: a bad
    // keystroke on an otherwise-valid value must reject just that
    // keystroke, not wipe the whole field.
    test('rejects a trailing third decimal digit WITHOUT clearing the field', () {
      expect(applyEdit(usdFormatter, '1.23', '1.234'), equals('1.23'));
    });

    test('rejects a stray letter mid-edit WITHOUT clearing the field', () {
      expect(applyEdit(usdFormatter, '12', '12a'), equals('12'));
    });

    test('rejects a second decimal point mid-edit WITHOUT clearing the field', () {
      expect(applyEdit(usdFormatter, '12.5', '12.5.'), equals('12.5'));
    });
  });

  group('LBP amount formatter (^\\d*\$)', () {
    test('accepts a clean integer value', () {
      expect(apply(lbpFormatter, '89500'), equals('89500'));
    });

    test('rejects Arabic-Indic digits', () {
      expect(apply(lbpFormatter, '١٢٣٤٥'), equals(''));
    });

    test('rejects full-width digits', () {
      expect(apply(lbpFormatter, '１２３４５'), equals(''));
    });

    test('rejects scientific notation', () {
      expect(apply(lbpFormatter, '1e10'), equals(''));
    });

    test('rejects a decimal point entirely (LBP has no cents)', () {
      expect(apply(lbpFormatter, '89500.00'), equals(''));
    });

    test('rejects pasted currency-symbol/comma strings', () {
      expect(apply(lbpFormatter, '\$1,234.56'), equals(''));
    });

    test('rejects a 500+ character string (contains letters)', () {
      expect(apply(lbpFormatter, 'A' * 500 + '123'), equals(''));
    });

    test('rejects emoji', () {
      expect(apply(lbpFormatter, '😀123'), equals(''));
    });

    test('rejects an embedded null byte', () {
      expect(apply(lbpFormatter, '12\u000034'), equals(''));
    });

    test('rejects a decimal point mid-edit WITHOUT clearing the field', () {
      expect(applyEdit(lbpFormatter, '895', '895.'), equals('895'));
    });
  });
}
