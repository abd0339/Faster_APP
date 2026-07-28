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
/// Call [initialize] once, right after a successful login —
/// it requests permission, gets the device's FCM token,
/// registers it with the backend, and sets up listeners for
/// incoming pushes (foreground + tap-to-open).
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  String? _currentToken;

  /// Called once after login. Wrapped so any failure here
  /// (permission denied, unsupported platform, etc.) can
  /// NEVER block login or break the rest of the app — push
  /// notifications are a nice-to-have, not a requirement.
  Future<void> initialize({
    required void Function(Map<String, dynamic> data) onNotificationTap,
  }) async {
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

      // ─── Token can rotate — re-register when it does ─
      messaging.onTokenRefresh.listen((newToken) {
        _registerToken(newToken);
      });

      // ─── Foreground messages ──────────────────────────
      // The OS doesn't show a system notification banner
      // automatically while the app is open — that's normal
      // FCM behavior. For now this just logs; a nicer
      // in-app banner can be added later without touching
      // any of the backend/registration logic above.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📬 Foreground push: ${message.notification?.title}');
      });

      // ─── User tapped a notification (app was in background) ─
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        onNotificationTap(message.data);
      });

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

  /// Called on logout — stops pushes from reaching a
  /// signed-out device.
  Future<void> unregister() async {
    if (_currentToken == null) return;
    try {
      await ApiService.instance
          .delete('${ApiConstants.unregisterDevice}?fcmToken=$_currentToken');
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