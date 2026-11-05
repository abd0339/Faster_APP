import 'package:firebase_messaging/firebase_messaging.dart';

/// A single entry in the on-device notification log — one row per push
/// notification received (or otherwise logged) by the app.
class NotificationEntry {
  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime receivedAt;
  final bool read;

  const NotificationEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.data,
    required this.receivedAt,
    this.read = false,
  });

  /// Builds a log entry from an incoming FCM [RemoteMessage].
  ///
  /// - `id` comes from `message.messageId`, falling back to the current
  ///   timestamp when the message has none.
  /// - `title`/`body` come from `message.notification`, defaulting to `''`
  ///   when there is no notification payload (data-only messages).
  /// - `data` is copied as-is from `message.data`.
  factory NotificationEntry.fromRemoteMessage(RemoteMessage message) {
    return NotificationEntry(
      id: message.messageId ?? DateTime.now().toIso8601String(),
      title: message.notification?.title ?? '',
      body: message.notification?.body ?? '',
      data: message.data,
      receivedAt: DateTime.now(),
    );
  }

  factory NotificationEntry.fromJson(Map<String, dynamic> json) {
    return NotificationEntry(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      data: json['data'] == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(json['data']),
      receivedAt: DateTime.tryParse(json['receivedAt'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: json['read'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'data': data,
      'receivedAt': receivedAt.toIso8601String(),
      'read': read,
    };
  }

  NotificationEntry copyWith({bool? read}) {
    return NotificationEntry(
      id: id,
      title: title,
      body: body,
      data: data,
      receivedAt: receivedAt,
      read: read ?? this.read,
    );
  }
}
