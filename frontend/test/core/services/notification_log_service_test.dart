import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:faster_app/core/models/notification_entry.dart';
import 'package:faster_app/core/services/notification_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  NotificationEntry buildEntry({
    String id = 'n1',
    String title = 'Title',
    String body = 'Body',
    Map<String, dynamic> data = const {'orderId': '1'},
    DateTime? receivedAt,
    bool read = false,
  }) {
    return NotificationEntry(
      id: id,
      title: title,
      body: body,
      data: data,
      receivedAt: receivedAt ?? DateTime.now(),
      read: read,
    );
  }

  group('NotificationLogService', () {
    test(
        'init then add then getAll round-trips an entry, and a fresh '
        'init() reload still finds it in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});

      final service = NotificationLogService.instance;
      await service.init();

      final entry = buildEntry(id: 'n1', title: 'Order ready');
      service.add(entry);

      final all = service.getAll();
      expect(all.length, 1);
      expect(all.first.id, 'n1');
      expect(all.first.title, 'Order ready');

      // Simulate a fresh reload (e.g. app restart) by calling init() again
      // — the persisted copy in SharedPreferences must still contain it.
      await service.init();
      final reloaded = service.getAll();
      expect(reloaded.length, 1);
      expect(reloaded.first.id, 'n1');
    });

    test('markRead flips read on the matching entry only', () async {
      SharedPreferences.setMockInitialValues({});

      final service = NotificationLogService.instance;
      await service.init();

      service.add(buildEntry(id: 'a', read: false));
      service.add(buildEntry(id: 'b', read: false));

      service.markRead('a');

      final all = service.getAll();
      final a = all.firstWhere((e) => e.id == 'a');
      final b = all.firstWhere((e) => e.id == 'b');

      expect(a.read, isTrue);
      expect(b.read, isFalse);
    });

    test('unreadCount reflects unread entries only', () async {
      SharedPreferences.setMockInitialValues({});

      final service = NotificationLogService.instance;
      await service.init();

      service.add(buildEntry(id: 'a', read: false));
      service.add(buildEntry(id: 'b', read: false));
      service.add(buildEntry(id: 'c', read: false));

      expect(service.unreadCount, 3);

      service.markRead('b');

      expect(service.unreadCount, 2);
    });

    test('adding a 51st entry drops the oldest, leaving 50 both in getAll() '
        'and in what is persisted', () async {
      SharedPreferences.setMockInitialValues({});

      final service = NotificationLogService.instance;
      await service.init();

      for (var i = 0; i < 50; i++) {
        service.add(buildEntry(id: 'id-$i'));
      }
      expect(service.getAll().length, 50);
      expect(service.getAll().any((e) => e.id == 'id-0'), isTrue);

      // 51st entry should push out the oldest (id-0).
      service.add(buildEntry(id: 'id-50'));

      final all = service.getAll();
      expect(all.length, 50);
      expect(all.any((e) => e.id == 'id-0'), isFalse);
      expect(all.any((e) => e.id == 'id-50'), isTrue);

      // Reload from persisted storage and check the cap held there too.
      await service.init();
      final reloaded = service.getAll();
      expect(reloaded.length, 50);
      expect(reloaded.any((e) => e.id == 'id-0'), isFalse);
      expect(reloaded.any((e) => e.id == 'id-50'), isTrue);
    });

    test(
        'init() completes without throwing and getAll() returns [] when '
        'SharedPreferences holds malformed JSON', () async {
      SharedPreferences.setMockInitialValues({
        'notification_log_v1': 'not valid json',
      });

      final service = NotificationLogService.instance;
      await service.init();

      expect(service.getAll(), isEmpty);
    });

    test(
        'add() and markRead() never throw even when an entry\'s data map '
        'is not JSON-serializable', () async {
      SharedPreferences.setMockInitialValues({});

      final service = NotificationLogService.instance;
      await service.init();

      // DateTime (and most non-primitive objects) cannot be jsonEncode'd
      // as-is — this stands in for a malformed/unexpected `data` payload.
      final badEntry = buildEntry(id: 'bad', data: {'when': DateTime.now()});

      expect(() => service.add(badEntry), returnsNormally);
      expect(service.getAll().any((e) => e.id == 'bad'), isTrue);

      expect(() => service.markRead('bad'), returnsNormally);
      expect(service.getAll().firstWhere((e) => e.id == 'bad').read, isTrue);
    });

    test('add() ignores an entry whose id is already in the log', () async {
      SharedPreferences.setMockInitialValues({});

      final service = NotificationLogService.instance;
      await service.init();

      service.add(buildEntry(id: 'dup', title: 'First'));
      service.add(buildEntry(id: 'dup', title: 'Second'));

      final all = service.getAll();
      expect(all.length, 1);
      expect(all.single.title, 'First');
      expect(service.unreadCount, 1);
    });

    test(
        'clear() empties the log in memory and on disk, so a later init() '
        'does not bring the previous account\'s entries back', () async {
      SharedPreferences.setMockInitialValues({});

      final service = NotificationLogService.instance;
      await service.init();
      service.add(buildEntry(id: 'a'));
      service.add(buildEntry(id: 'b'));
      // Let the fire-and-forget persist land first, so clear() has
      // something on disk to remove.
      await Future<void>.delayed(Duration.zero);

      await service.clear();

      expect(service.getAll(), isEmpty);
      expect(service.unreadCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notification_log_v1'), isNull);

      await service.init();
      expect(service.getAll(), isEmpty);
    });

    test('add(), markRead() and clear() notify listeners; no-op calls do not',
        () async {
      SharedPreferences.setMockInitialValues({});

      final service = NotificationLogService.instance;
      await service.init();

      var notifications = 0;
      void listener() => notifications++;
      service.addListener(listener);
      addTearDown(() => service.removeListener(listener));

      service.add(buildEntry(id: 'a'));
      expect(notifications, 1);

      service.add(buildEntry(id: 'a')); // duplicate id
      expect(notifications, 1);

      service.markRead('a');
      expect(notifications, 2);

      service.markRead('a'); // already read
      service.markRead('missing');
      expect(notifications, 2);

      await service.clear();
      expect(notifications, 3);
    });

    test(
        'an entry added while init() is still loading is kept alongside the '
        'persisted history', () async {
      final service = NotificationLogService.instance;
      // Start from an empty in-memory log, then seed the disk copy.
      await service.clear();
      SharedPreferences.setMockInitialValues({
        'notification_log_v1':
            '[{"id":"old","title":"Old","body":"","data":{},'
                '"receivedAt":"2026-01-01T10:00:00.000","read":true}]',
      });

      final loading = service.init();
      service.add(buildEntry(id: 'early'));
      await loading;

      final ids = service.getAll().map((e) => e.id).toList();
      expect(ids, ['early', 'old']);

      // The merged list, not just the early entry, is what got persisted.
      await Future<void>.delayed(Duration.zero);
      await service.init();
      expect(service.getAll().map((e) => e.id).toList(), ['early', 'old']);
    });
  });

  group('NotificationEntry.fromRemoteMessage', () {
    test('maps id, title, body and data from a RemoteMessage', () {
      const message = RemoteMessage(
        messageId: 'm1',
        notification: RemoteNotification(title: 't', body: 'b'),
        data: {'orderId': '5'},
      );

      final entry = NotificationEntry.fromRemoteMessage(message);

      expect(entry.id, 'm1');
      expect(entry.title, 't');
      expect(entry.body, 'b');
      expect(entry.data, {'orderId': '5'});
    });

    test('defaults title/body to empty string when notification is null',
        () {
      const message = RemoteMessage(
        messageId: 'm2',
        data: {'orderId': '6'},
      );

      final entry = NotificationEntry.fromRemoteMessage(message);

      expect(entry.id, 'm2');
      expect(entry.title, '');
      expect(entry.body, '');
      expect(entry.data, {'orderId': '6'});
    });
  });
}
