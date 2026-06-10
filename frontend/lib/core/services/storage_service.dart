import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // ─── Keys ─────────────────────────────────────────
  static const String _tokenKey = 'auth_token';
  static const String _roleKey = 'user_role';
  static const String _userIdKey = 'user_id';
  static const String _fullNameKey = 'full_name';
  static const String _emailKey = 'user_email';
  static const String _phoneKey = 'user_phone';

  // ─── Save after login/register ────────────────────
  Future<void> saveAuthData({
    required String token,
    required String role,
    required String fullName,
    required String email,
    required String phone,
  }) async {
    await Future.wait([
      _storage.write(key: _tokenKey, value: token),
      _storage.write(key: _roleKey, value: role),
      _storage.write(key: _fullNameKey, value: fullName),
      _storage.write(key: _emailKey, value: email),
      _storage.write(key: _phoneKey, value: phone),
    ]);
  }

  // ─── Save user ID separately ──────────────────────
  Future<void> saveUserId(String id) async {
    await _storage.write(key: _userIdKey, value: id);
  }

  // ─── Read token ───────────────────────────────────
  Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  // ─── Read role ────────────────────────────────────
  Future<String?> getRole() async {
    return _storage.read(key: _roleKey);
  }

  // ─── Read user ID ─────────────────────────────────
  Future<String?> getUserId() async {
    return _storage.read(key: _userIdKey);
  }

  // ─── Read full name ───────────────────────────────
  Future<String?> getFullName() async {
    return _storage.read(key: _fullNameKey);
  }

  // ─── Read email ───────────────────────────────────
  Future<String?> getEmail() async {
    return _storage.read(key: _emailKey);
  }

  // ─── Read phone ───────────────────────────────────
  Future<String?> getPhone() async {
    return _storage.read(key: _phoneKey);
  }

  // ─── Check if logged in ───────────────────────────
  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // ─── Clear on logout ──────────────────────────────
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
