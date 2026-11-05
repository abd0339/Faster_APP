import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:faster_app/core/models/notification_entry.dart';
import 'package:faster_app/core/router/app_router.dart';
import 'package:faster_app/core/services/notification_log_service.dart';
import 'package:faster_app/features/customer/screens/customer_order_tracking_screen.dart';
import 'package:faster_app/shared/screens/notification_center_screen.dart';
import 'package:faster_app/shared/widgets/app_empty_state.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

NotificationEntry _buildEntry({
  required String id,
  String title = 'Title',
  Map<String, dynamic> data = const {},
  bool read = false,
  DateTime? receivedAt,
}) {
  return NotificationEntry(
    id: id,
    title: title,
    body: 'body',
    data: data,
    receivedAt: receivedAt ?? DateTime(2026, 1, 1, 10, 30),
    read: read,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Tapping a notification can navigate to CustomerOrderTrackingScreen,
    // which talks to the backend and to secure storage — every such call
    // must fail fast rather than hang on a real network timeout or throw
    // from a missing platform channel.
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://127.0.0.1:1');
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('NotificationCenterScreen', () {
    testWidgets(
        'renders seeded entries newest first, with the unread one bold '
        'and the read one normal weight', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();
      // add() inserts at the front, so this seeding order makes "Third one"
      // the newest and "First one" the oldest — getAll() (and therefore the
      // rendered list) must show them in that newest-first order:
      // Third, Second, First.
      service.add(_buildEntry(id: 'e1', title: 'First one', read: true));
      service.add(_buildEntry(id: 'e2', title: 'Second one', read: true));
      service.add(
          _buildEntry(id: 'e3', title: 'Third one', read: false));

      await tester.pumpWidget(
        const MaterialApp(home: NotificationCenterScreen()),
      );
      await tester.pump();

      expect(find.text('First one'), findsOneWidget);
      expect(find.text('Second one'), findsOneWidget);
      expect(find.text('Third one'), findsOneWidget);

      // Assert actual on-screen vertical order, not just presence — a
      // list rendered oldest-first would still pass a presence-only check.
      final firstY = tester.getTopLeft(find.text('First one')).dy;
      final secondY = tester.getTopLeft(find.text('Second one')).dy;
      final thirdY = tester.getTopLeft(find.text('Third one')).dy;
      expect(thirdY, lessThan(secondY));
      expect(secondY, lessThan(firstY));

      final unreadTitle = tester.widget<Text>(find.text('Third one'));
      final readTitle = tester.widget<Text>(find.text('First one'));

      expect(unreadTitle.style?.fontWeight, FontWeight.w700);
      expect(readTitle.style?.fontWeight, FontWeight.w400);
    });

    testWidgets(
        'tapping an entry marks it read and navigates to order tracking',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();
      service.add(_buildEntry(
        id: 'tap-1',
        title: 'Order update',
        data: {'orderId': '42', 'trackingCode': 'ABC123'},
        read: false,
      ));

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const NotificationCenterScreen(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Order update'));
      // Give the push transition time to complete without using
      // pumpAndSettle, which would wait indefinitely on the destination
      // screen's background reconnect timers.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        service.getAll().firstWhere((e) => e.id == 'tap-1').read,
        isTrue,
      );
      expect(find.byType(CustomerOrderTrackingScreen), findsOneWidget);
    });

    testWidgets(
        'tapping an entry with no orderId/trackingCode marks it read and '
        'does not navigate anywhere', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();
      service.add(_buildEntry(id: 'no-nav', title: 'No nav', read: false));

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const NotificationCenterScreen(),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('No nav'));
      await tester.pump();

      expect(
        service.getAll().firstWhere((e) => e.id == 'no-nav').read,
        isTrue,
      );
      expect(find.byType(NotificationCenterScreen), findsOneWidget);
      expect(find.byType(CustomerOrderTrackingScreen), findsNothing);
    });

    testWidgets('a notification that arrives while the screen is open appears '
        'without leaving the screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();

      await tester.pumpWidget(
        const MaterialApp(home: NotificationCenterScreen()),
      );
      await tester.pump();
      expect(find.byType(AppEmptyState), findsOneWidget);

      service.add(_buildEntry(id: 'live', title: 'Arrived live'));
      await tester.pump();

      expect(find.byType(AppEmptyState), findsNothing);
      expect(find.text('Arrived live'), findsOneWidget);
    });

    testWidgets(
        'empty log renders AppEmptyState with the "No notifications yet" '
        'message', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();

      await tester.pumpWidget(
        const MaterialApp(home: NotificationCenterScreen()),
      );
      await tester.pump();

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });
  });
}
