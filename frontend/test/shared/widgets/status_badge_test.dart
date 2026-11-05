import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/shared/widgets/status_badge.dart';

/// Matches any character in the common emoji ranges, mirroring the emoji
/// StatusBadge labels used to be prefixed with.
final _emojiPattern = RegExp(
  r'[\u{1F000}-\u{1FFFF}\u{2190}-\u{2BFF}\u{2600}-\u{27BF}\u{FE0F}]',
  unicode: true,
);

void main() {
  Future<void> pumpBadge(
    WidgetTester tester, {
    required String status,
    bool isRide = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: status, isRide: isRide),
        ),
      ),
    );
  }

  testWidgets('PENDING renders no emoji, label "Pending", and schedule icon',
      (tester) async {
    await pumpBadge(tester, status: 'PENDING');

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'Pending');
    expect(_emojiPattern.hasMatch(text.data!), isFalse);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.schedule_rounded);
  });

  testWidgets(
      'DELIVERED renders no emoji, label "Delivered", and check_circle icon',
      (tester) async {
    await pumpBadge(tester, status: 'DELIVERED');

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'Delivered');
    expect(_emojiPattern.hasMatch(text.data!), isFalse);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.check_circle_rounded);
  });

  testWidgets(
      'DISPUTED renders no emoji, label "Disputed", and report_problem icon',
      (tester) async {
    await pumpBadge(tester, status: 'DISPUTED');

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'Disputed');
    expect(_emojiPattern.hasMatch(text.data!), isFalse);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.report_problem_rounded);
  });

  testWidgets('ONLINE renders no emoji, label "Online", and filled circle icon',
      (tester) async {
    await pumpBadge(tester, status: 'ONLINE');

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'Online');
    expect(_emojiPattern.hasMatch(text.data!), isFalse);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.circle);
  });

  testWidgets(
      'PICKED_UP with isRide:true renders "On the way" and a bike icon',
      (tester) async {
    await pumpBadge(tester, status: 'PICKED_UP', isRide: true);

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'On the way');
    expect(_emojiPattern.hasMatch(text.data!), isFalse);

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.directions_bike_rounded);
  });
}
