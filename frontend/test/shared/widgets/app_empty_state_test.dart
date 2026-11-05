import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/shared/widgets/app_empty_state.dart';
import 'package:faster_app/shared/widgets/app_button.dart';

void main() {
  group('AppEmptyState', () {
    testWidgets('renders the icon and message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              icon: Icons.inbox_outlined,
              message: 'Nothing here yet',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('does not render an action button when actionLabel is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              icon: Icons.inbox_outlined,
              message: 'Nothing here yet',
            ),
          ),
        ),
      );

      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets(
        'renders an AppButton with actionLabel and fires onAction on tap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppEmptyState(
              icon: Icons.inbox_outlined,
              message: 'Nothing here yet',
              actionLabel: 'Refresh',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byType(AppButton), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
