import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:faster_app/core/services/push_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushNotificationService.initialize', () {
    test(
        'accepts an optional onForegroundMessage callback alongside '
        'onNotificationTap and completes without throwing when Firebase '
        'is not initialized in the test environment (same '
        'try/catch-and-swallow contract as the rest of initialize)',
        () async {
      var tapCalled = false;
      var foregroundCalled = false;

      await expectLater(
        PushNotificationService.instance.initialize(
          onNotificationTap: (data) {
            tapCalled = true;
          },
          onForegroundMessage: (RemoteMessage message) {
            foregroundCalled = true;
          },
        ),
        completes,
      );

      // Firebase isn't initialized in this test environment, so
      // requestPermission() throws immediately and initialize()'s own
      // try/catch swallows it before either listener is ever wired up —
      // neither callback should have fired.
      expect(tapCalled, isFalse);
      expect(foregroundCalled, isFalse);
    });

    test('still works when onForegroundMessage is omitted (it is optional)',
        () async {
      await expectLater(
        PushNotificationService.instance.initialize(
          onNotificationTap: (data) {},
        ),
        completes,
      );
    });
  });
}
