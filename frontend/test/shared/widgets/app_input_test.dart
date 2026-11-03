import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/shared/widgets/app_input.dart';
import 'package:faster_app/core/utils/currency_input_formatter.dart';

void main() {
  testWidgets('AppInput applies inputFormatters and maxLength', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppInput(
      hint: 'x', controller: controller,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 5,
    ))));
    await tester.enterText(find.byType(TextFormField), 'abc123456');
    expect(controller.text, '12345'); // letters stripped, truncated to 5
  });

  // Final review fix wave, finding #4 — the real defense against a
  // long digit string parsing to Infinity (double.tryParse('1'*309+)
  // is already Infinity, not null, so a bare `<= 0` check never
  // catches it) is maxLength on the AppInput field itself, not the
  // currency shape-formatter (see price_input_formatter_test.dart's
  // own comment on why the regex alone can't catch this). This proves
  // the combination actually works end to end, the way the price
  // fields in merchant_dashboard_screen.dart /
  // customer_dashboard_screen.dart wire it up.
  testWidgets(
      'USD price field truncates a long digit string to a finite, '
      'parseable value', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppInput(
      hint: '0.00',
      controller: controller,
      inputFormatters: [CurrencyInputFormatter.usd()],
      maxLength: 10,
      counterText: '',
    ))));

    await tester.enterText(find.byType(TextFormField), '1' * 500);

    expect(controller.text.length, lessThanOrEqualTo(10));
    final parsed = double.tryParse(controller.text);
    expect(parsed, isNotNull);
    expect(parsed!.isFinite, isTrue);
  });

  testWidgets(
      'LBP amount field truncates a long digit string to a finite, '
      'parseable value', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppInput(
      hint: '0',
      controller: controller,
      inputFormatters: [CurrencyInputFormatter.lbp()],
      maxLength: 12,
      counterText: '',
    ))));

    await tester.enterText(find.byType(TextFormField), '9' * 500);

    expect(controller.text.length, lessThanOrEqualTo(12));
    final parsed = double.tryParse(controller.text);
    expect(parsed, isNotNull);
    expect(parsed!.isFinite, isTrue);
  });

  testWidgets('AppInput suppresses the default maxLength counter when '
      'counterText is empty', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppInput(
      hint: 'x',
      maxLength: 5,
      counterText: '',
    ))));

    expect(find.text('0/5'), findsNothing);
  });
}
