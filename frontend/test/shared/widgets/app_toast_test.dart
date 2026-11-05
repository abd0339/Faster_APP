import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/core/constants/app_colors.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

/// Pumps a minimal app (MaterialApp supplies the Navigator + Overlay) and
/// returns a context from inside the Scaffold to call AppToast with.
Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return captured;
}

Icon _iconWidget(WidgetTester tester, IconData icon) =>
    tester.widget<Icon>(find.byIcon(icon));

void main() {
  tearDown(AppToast.debugReset);

  group('AppToast', () {
    testWidgets(
        '(a) success shows message with success icon/color and '
        'auto-dismisses after 4 seconds', (tester) async {
      final context = await _pumpHost(tester);

      AppToast.success(context, 'Order placed');
      await tester.pump();

      expect(find.text('Order placed'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(
        _iconWidget(tester, Icons.check_circle_rounded).color,
        AppColors.success,
      );

      // Still visible just before the 4s mark.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Order placed'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Order placed'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('each variant uses its own icon and color', (tester) async {
      final context = await _pumpHost(tester);
      final cases = <void Function(BuildContext, String), (IconData, Color)>{
        (c, m) => AppToast.success(c, m): (
          Icons.check_circle_rounded,
          AppColors.success
        ),
        (c, m) => AppToast.error(c, m): (Icons.cancel_rounded, AppColors.error),
        (c, m) => AppToast.warning(c, m): (
          Icons.warning_rounded,
          AppColors.warning
        ),
        (c, m) => AppToast.info(c, m): (Icons.info_rounded, AppColors.info),
      };

      for (final entry in cases.entries) {
        final (icon, color) = entry.value;
        entry.key(context, 'msg');
        await tester.pump();
        expect(find.byIcon(icon), findsOneWidget);
        expect(_iconWidget(tester, icon).color, color);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(find.byIcon(icon), findsNothing);
      }
    });

    testWidgets(
        '(b) a toast with an action does not auto-dismiss; tapping the '
        'action calls onAction and removes the toast', (tester) async {
      final context = await _pumpHost(tester);
      var calls = 0;

      AppToast.error(
        context,
        'Retry?',
        actionLabel: 'Retry',
        onAction: () => calls++,
      );
      await tester.pump();

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Retry?'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(calls, 0);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Retry?'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets(
        '(c) a same-variant toast interrupts the current one, leaving only '
        'the second visible', (tester) async {
      final context = await _pumpHost(tester);

      AppToast.error(context, 'First error');
      AppToast.error(context, 'Second error');
      await tester.pump();

      expect(find.text('First error'), findsNothing);
      expect(find.text('Second error'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);

      // The interrupted toast's timer must not dismiss the new one early,
      // and the new one gets its own full 4 seconds.
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Second error'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Second error'), findsNothing);
    });

    testWidgets(
        '(d) a different-variant toast is queued and shown after the '
        'current one is dismissed', (tester) async {
      final context = await _pumpHost(tester);

      AppToast.error(context, 'Payment failed');
      AppToast.success(context, 'Saved draft');
      await tester.pump();

      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.text('Saved draft'), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(find.text('Payment failed'), findsNothing);
      expect(find.text('Saved draft'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      // The queued toast auto-dismisses on its own 4-second timer.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Saved draft'), findsNothing);
    });

    testWidgets('queued toasts are shown in FIFO order', (tester) async {
      final context = await _pumpHost(tester);

      AppToast.error(context, 'one');
      AppToast.success(context, 'two');
      AppToast.warning(context, 'three');
      await tester.pump();
      expect(find.text('one'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsNothing);
      expect(find.text('two'), findsOneWidget);
      expect(find.text('three'), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('two'), findsNothing);
      expect(find.text('three'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('three'), findsNothing);
    });

    testWidgets(
        'tapping an action shows the next queued toast', (tester) async {
      final context = await _pumpHost(tester);

      // The sticky toast comes off the queue with another request still
      // waiting behind it.
      AppToast.info(context, 'Syncing');
      AppToast.error(context, 'Retry?', actionLabel: 'Retry', onAction: () {});
      AppToast.warning(context, 'Low balance');
      await tester.pump();

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Syncing'), findsNothing);
      expect(find.text('Retry?'), findsOneWidget);
      expect(find.text('Low balance'), findsNothing);

      // Sticky: still up well past the auto-dismiss window.
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Retry?'), findsOneWidget);
      expect(find.text('Low balance'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Retry?'), findsNothing);
      expect(find.text('Low balance'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Low balance'), findsNothing);
    });

    testWidgets(
        'a different-variant toast interrupts a sticky action toast instead '
        'of waiting behind it', (tester) async {
      final context = await _pumpHost(tester);
      var calls = 0;

      AppToast.error(
        context,
        'Retry?',
        actionLabel: 'Retry',
        onAction: () => calls++,
      );
      await tester.pump();
      AppToast.success(context, 'Back online');
      await tester.pump();

      expect(find.text('Retry?'), findsNothing);
      expect(find.text('Back online'), findsOneWidget);
      expect(calls, 0);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Back online'), findsNothing);
    });

    testWidgets(
        'a new request interrupts a sticky toast immediately, ahead of '
        'requests already queued behind it', (tester) async {
      final context = await _pumpHost(tester);

      // The sticky toast comes off the queue with 'Low balance' still
      // waiting behind it.
      AppToast.info(context, 'Syncing');
      AppToast.error(context, 'Retry?', actionLabel: 'Retry', onAction: () {});
      AppToast.warning(context, 'Low balance');
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Retry?'), findsOneWidget);

      AppToast.success(context, 'Back online');
      await tester.pump();

      // Shown right away, not queued behind 'Low balance'.
      expect(find.text('Retry?'), findsNothing);
      expect(find.text('Back online'), findsOneWidget);
      expect(find.text('Low balance'), findsNothing);

      // The queue resumes once the interrupting toast finishes.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Back online'), findsNothing);
      expect(find.text('Low balance'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Low balance'), findsNothing);
    });

    testWidgets(
        'a toast shown from inside onAction survives the action toast\'s '
        'own removal', (tester) async {
      final context = await _pumpHost(tester);

      AppToast.error(
        context,
        'Retry?',
        actionLabel: 'Retry',
        onAction: () => AppToast.error(context, 'Still failing'),
      );
      await tester.pump();

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Retry?'), findsNothing);
      expect(find.text('Still failing'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Still failing'), findsNothing);
    });
  });
}
