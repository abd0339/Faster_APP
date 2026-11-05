import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/admin/screens/admin_dashboard_screen.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      null;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      false;

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      {};

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
}

/// Fails every request immediately with a [SocketException], so the
/// exchange-rate load (and the stats load running beside it) take the
/// error path without touching a real socket.
class _RefusingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return Future<HttpClientRequest>.error(
      const SocketException('Connection refused (test)'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://localhost:8080');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  tearDown(AppToast.debugReset);

  testWidgets(
      'a failed exchange-rate load shows an AppToast error, not a SnackBar',
      (tester) async {
    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: AdminDashboardScreen()),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Same fixed message ApiService.getErrorMessage gives for a
        // connection error; see frontend/lib/core/services/api_service.dart.
        expect(
          find.text('Cannot connect to server. Is the backend running?'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);

        await tester.pump(AppToast.displayDuration);
        await tester.pump();
      },
      createHttpClient: (context) => _RefusingHttpClient(),
    );
  });
}
