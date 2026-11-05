import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/customer/screens/customer_store_menu_screen.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

import '../../../helpers/fake_http.dart';

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

/// JSON body to return per path; anything unmatched (e.g. the offers
/// endpoint) gets `[]`.
final Map<String, String> _responses = {};

Future<HttpClientRequest> _route(Uri url) async {
  final body = _responses[url.path] ?? '[]';
  return FakeHttpClientRequest(FakeHttpClientResponse(body));
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://localhost:8080');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
    // Installed once, globally: see RoutingHttpClient's doc comment for
    // why a per-test HttpOverrides.runZoned wrapper wouldn't work here.
    HttpOverrides.global = TestHttpOverrides(RoutingHttpClient(_route));
  });

  tearDown(() {
    AppToast.debugReset();
    _responses.clear();
  });

  testWidgets(
      'adding a menu item to the cart shows an AppToast success, not a '
      'SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final menuJson = jsonEncode({
      'menu': [
        {
          'name': 'Mains',
          'icon': '',
          'items': [
            {
              'id': 1,
              'name': 'Burger',
              'price': 5.0,
              'imageUrl': null,
              'isAvailable': true,
              'isSnoozed': false,
              'description': null,
            },
          ],
        },
      ],
    });
    final statusJson = jsonEncode({'isOpen': true});

    _responses.addAll({
      '/api/store/42/menu': menuJson,
      '/api/store/42/status': statusJson,
      '/api/store/42/offers': '[]',
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: CustomerStoreMenuScreen(
          merchantId: 42,
          merchantName: 'Test Merchant',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.ensureVisible(find.byIcon(Icons.add_rounded).first);
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();

    expect(find.text('Burger added to cart'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pump();
  });
}
