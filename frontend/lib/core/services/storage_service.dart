import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// On Web: flutter_secure_storage throws OperationError (Web Crypto API
/// incompatibility). We fall back to SharedPreferences on Web, and keep
/// FlutterSecureStorage on Android / iOS / Desktop.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  // ─── Secure storage (mobile/desktop only) ─────────
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ─── Keys ─────────────────────────────────────────
  static const String _tokenKey = 'auth_token';
  static const String _roleKey = 'user_role';
  static const String _userIdKey = 'user_id';
  static const String _fullNameKey = 'full_name';
  static const String _emailKey = 'user_email';
  static const String _phoneKey = 'user_phone';

  // ─── Low-level read/write (platform-aware) ────────
  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    } else {
      return _secureStorage.read(key: key);
    }
  }

  Future<void> _deleteAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } else {
      await _secureStorage.deleteAll();
    }
  }

  // ─── Save after login/register ────────────────────
  Future<void> saveAuthData({
    required String token,
    required String role,
    required String fullName,
    required String email,
    required String phone,
  }) async {
    await Future.wait([
      _write(_tokenKey, token),
      _write(_roleKey, role),
      _write(_fullNameKey, fullName),
      _write(_emailKey, email),
      _write(_phoneKey, phone),
    ]);
  }

  // ─── Save user ID separately ──────────────────────
  Future<void> saveUserId(String id) async {
    await _write(_userIdKey, id);
  }

  // ─── Read token ───────────────────────────────────
  Future<String?> getToken() async => _read(_tokenKey);

  // ─── Read role ────────────────────────────────────
  Future<String?> getRole() async => _read(_roleKey);

  // ─── Read user ID ─────────────────────────────────
  Future<String?> getUserId() async => _read(_userIdKey);

  // ─── Read full name ───────────────────────────────
  Future<String?> getFullName() async => _read(_fullNameKey);

  // ─── Read email ───────────────────────────────────
  Future<String?> getEmail() async => _read(_emailKey);

  // ─── Read phone ───────────────────────────────────
  Future<String?> getPhone() async => _read(_phoneKey);

  // ─── Check if logged in ───────────────────────────
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ─── Clear on logout ──────────────────────────────
  Future<void> clearAll() async => _deleteAll();
}
