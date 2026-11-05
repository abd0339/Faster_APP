import 'dart:async' show StreamSubscription;
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import '../constants/api_constants.dart';
import 'api_service.dart';

/// PushNotificationService — Phase 4 (FCM)
/// ────────────────────────────────────────────────────
/// Purely ADDITIVE alongside the existing WebSocket
/// (real-time while app is open) and Twilio (WhatsApp/SMS)
/// channels — this adds actual OS-level push notifications
/// that arrive even when the app is closed/backgrounded.
///
/// Call [initialize] right after each successful login —
/// it requests permission, gets the device's FCM token,
/// registers it with the backend, and sets up listeners for
/// incoming pushes (foreground + tap-to-open).
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  String? _currentToken;

  /// Listeners wired by [initialize]. Kept so a later [initialize] (the
  /// next login in the same app process) replaces them instead of stacking
  /// a second set, which would handle every push twice.
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  /// Called after every login. Wrapped so any failure here
  /// (permission denied, unsupported platform, etc.) can
  /// NEVER block login or break the rest of the app — push
  /// notifications are a nice-to-have, not a requirement.
  ///
  /// Safe to call repeatedly: listeners from an earlier call are
  /// cancelled first, so only the latest callbacks are ever active.
  Future<void> initialize({
    required void Function(Map<String, dynamic> data) onNotificationTap,
    void Function(RemoteMessage message)? onForegroundMessage,
  }) async {
    _cancelSubscriptions();
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('⚠️ Push notification permission denied by user');
        return;
      }

      // ─── Get and register the device token ──────────
      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }

      // Cancelled again here, with no await between this and the listen()
      // calls below, so two overlapping initialize() calls still end up
      // with exactly one set of listeners.
      _cancelSubscriptions();

      // ─── Token can rotate — re-register when it does ─
      _subscriptions.add(messaging.onTokenRefresh.listen((newToken) {
        _registerToken(newToken);
      }));

      // ─── Foreground messages ──────────────────────────
      // The OS doesn't show a system notification banner
      // automatically while the app is open — that's normal
      // FCM behavior. For now this just logs; a nicer
      // in-app banner can be added later without touching
      // any of the backend/registration logic above.
      _subscriptions
          .add(FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📬 Foreground push: ${message.notification?.title}');
        // Guarded on its own: this listener callback runs well after
        // initialize()'s own try/catch above has already returned, so an
        // exception here would otherwise surface as an uncaught async
        // error instead of being swallowed like every other failure in
        // this class.
        try {
          onForegroundMessage?.call(message);
        } catch (e) {
          debugPrint('⚠️ onForegroundMessage callback failed: $e');
        }
      }));

      // ─── User tapped a notification (app was in background) ─
      _subscriptions.add(
          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        onNotificationTap(message.data);
      }));

      // ─── App was fully closed, opened via notification tap ─
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        onNotificationTap(initialMessage.data);
      }
    } catch (e) {
      debugPrint('⚠️ Push notification setup failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      _currentToken = token;
      await ApiService.instance.post(
        ApiConstants.registerDevice,
        data: {
          'fcmToken': token,
          'platform': _platformName(),
        },
      );
    } catch (e) {
      // Never let a registration failure surface to the
      // user — push is additive, not required.
      debugPrint('⚠️ Device token registration failed: $e');
    }
  }

  /// Cancels every listener wired by [initialize]. Fire-and-forget: the
  /// subscriptions stop delivering events as soon as cancel() is called.
  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      // ignore: discarded_futures
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  /// Called on logout — stops pushes from reaching a
  /// signed-out device, and detaches the listeners [initialize] wired so
  /// nothing is handled on behalf of the signed-out account.
  Future<void> unregister() async {
    _cancelSubscriptions();
    if (_currentToken == null) return;
    try {
      // FIX: FCM tokens can contain characters (like +, /, =)
      // that aren't safe raw in a URL query string — must be
      // percent-encoded, or Spring rejects the request with a
      // 400 "bad syntax" error before it even reaches our code.
      final encodedToken = Uri.encodeComponent(_currentToken!);
      await ApiService.instance
          .delete('${ApiConstants.unregisterDevice}?fcmToken=$encodedToken');
    } catch (e) {
      debugPrint('⚠️ Device token unregistration failed: $e');
    } finally {
      _currentToken = null;
    }
  }

  String _platformName() {
    if (kIsWeb) return 'WEB';
    if (Platform.isAndroid) return 'ANDROID';
    if (Platform.isIOS) return 'IOS';
    return 'UNKNOWN';
  }
}
