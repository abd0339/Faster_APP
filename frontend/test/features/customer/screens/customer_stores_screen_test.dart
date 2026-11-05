import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/customer/screens/customer_stores_screen.dart';
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

/// Fails every request immediately with a [SocketException], the same
/// way a real "backend not running" connection refusal looks to Dio —
/// without this screen's test ever attempting a real socket connection
/// (which this sandbox's network can leave hanging instead of quickly
/// refusing, making the test slow and flaky).
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
    // StorageService reads the auth token via flutter_secure_storage on
    // every request (even public ones) — no platform channel exists in
    // widget tests, so give it a working fake instead.
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
  });

  tearDown(AppToast.debugReset);

  testWidgets(
      'a failed store list load shows an AppToast error, not a SnackBar',
      (tester) async {
    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CustomerStoresScreen())),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // The fake client's SocketException is turned by Dio's IO adapter
        // into a DioException(type: connectionError), which
        // ApiService.getErrorMessage maps to this fixed string — see
        // frontend/lib/core/services/api_service.dart:134-151.
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
