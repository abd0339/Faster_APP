import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:faster_app/core/models/notification_entry.dart';
import 'package:faster_app/core/services/notification_log_service.dart';
import 'package:faster_app/shared/screens/notification_center_screen.dart';
import 'package:faster_app/shared/widgets/notification_bell_button.dart';

NotificationEntry _unreadEntry(String id) {
  return NotificationEntry(
    id: id,
    title: 'Title $id',
    body: 'body',
    data: const {},
    receivedAt: DateTime(2026, 1, 1, 10, 30),
    read: false,
  );
}

void main() {
  group('NotificationBellButton', () {
    testWidgets(
        'shows the unread count badge and navigates to '
        'NotificationCenterScreen on tap', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();
      service.add(_unreadEntry('n1'));
      service.add(_unreadEntry('n2'));

      await tester.pumpWidget(
        const MaterialApp(home: NotificationBellButton()),
      );
      await tester.pump();

      // Two unread entries -> filled bell icon, badge showing '2'.
      expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);

      final badge = tester.widget<badges.Badge>(find.byType(badges.Badge));
      expect(badge.showBadge, isTrue);
      expect((badge.badgeContent as Text).data, '2');

      await tester.tap(find.byIcon(Icons.notifications_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationCenterScreen), findsOneWidget);
    });

    testWidgets(
        'with no unread entries shows the outline icon and hides the badge',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();

      await tester.pumpWidget(
        const MaterialApp(home: NotificationBellButton()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_rounded), findsNothing);

      final badge = tester.widget<badges.Badge>(find.byType(badges.Badge));
      expect(badge.showBadge, isFalse);
    });

    testWidgets(
        'a const bell updates its badge when a notification arrives, with '
        'no parent rebuild', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();

      await tester.pumpWidget(
        const MaterialApp(home: NotificationBellButton()),
      );
      await tester.pump();

      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

      // A notification arrives after the bell already built once. Nothing
      // rebuilds the parent; the bell must pick this up on its own.
      service.add(_unreadEntry('late'));
      await tester.pump();

      expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
      final badge = tester.widget<badges.Badge>(find.byType(badges.Badge));
      expect(badge.showBadge, isTrue);
      expect((badge.badgeContent as Text).data, '1');
    });

    testWidgets(
        'clears the badge after the entries are read in the notification '
        'center and the user navigates back', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();
      service.add(_unreadEntry('n1'));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NotificationBellButton())),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.notifications_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationCenterScreen), findsOneWidget);

      service.markRead('n1');
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
      final badge = tester.widget<badges.Badge>(find.byType(badges.Badge));
      expect(badge.showBadge, isFalse);
    });

    testWidgets('clears the badge when the log is cleared (logout)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = NotificationLogService.instance;
      await service.init();
      service.add(_unreadEntry('n1'));

      await tester.pumpWidget(
        const MaterialApp(home: NotificationBellButton()),
      );
      await tester.pump();
      expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);

      await service.clear();
      await tester.pump();

      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });
  });
}
