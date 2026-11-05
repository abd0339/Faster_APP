import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:faster_app/core/constants/api_constants.dart';
import 'package:faster_app/features/customer/screens/public_tracking_screen.dart';
import 'package:faster_app/shared/widgets/app_skeleton_card.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

import '../../../helpers/fake_http.dart';

const _trackingCode = 'TRK123';

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

/// Always denies, so LocationService.getCurrentPosition() cleanly
/// returns null (no plugin channel involved) instead of throwing.
class _DeniedGeolocatorPlatform extends GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;
}

/// Routes requests by path so the screen's own tracking-data fetch
/// (`/api/tracking/public/TRK123`) can be driven per-test. Everything
/// else fails immediately — this screen's only other endpoint (sharing
/// location) isn't reached unless the device actually has a position,
/// which the denied geolocator platform above never provides.
class _TrackingRouting {
  Future<HttpClientRequest> Function(Uri url)? dataResponder;

  Future<HttpClientRequest> route(Uri url) {
    if (url.path == ApiConstants.publicTrackingData(_trackingCode)) {
      if (dataResponder != null) return dataResponder!(url);
      return Future.value(
        FakeHttpClientRequest(FakeHttpClientResponse('{}')),
      );
    }
    return Future.error(const SocketException('Connection refused'));
  }
}

Widget _buildApp({MediaQueryData? mediaQueryData}) {
  const app = MaterialApp(
    home: PublicTrackingScreen(trackingCode: _trackingCode),
  );
  if (mediaQueryData == null) return app;
  return MediaQuery(data: mediaQueryData, child: app);
}

void main() {
  final routing = _TrackingRouting();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://localhost:8080');
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
    GeolocatorPlatform.instance = _DeniedGeolocatorPlatform();
    HttpOverrides.global = TestHttpOverrides(RoutingHttpClient(routing.route));
  });

  tearDown(() {
    AppToast.debugReset();
    routing.dataResponder = null;
  });

  testWidgets(
      'sharing location without permission shows an AppToast error, not a '
      'SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final orderJson = jsonEncode({
      'status': 'PENDING',
      'trackingCode': _trackingCode,
      'grandTotal': 10.0,
      'deliveryFee': 2.0,
      'deliveryAddress': '123 Main St',
      'deliveryLat': null,
      'driverName': null,
    });
    routing.dataResponder = (_) async =>
        FakeHttpClientRequest(FakeHttpClientResponse(orderJson));

    await tester.pumpWidget(_buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.ensureVisible(find.text('Share My Location'));
    await tester.tap(find.text('Share My Location'));
    await tester.pump();

    expect(
      find.text('Could not get your location. Please allow location '
          'access.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pump();

    // Dispose the screen (cancels its 8s poll Timer) before the test
    // ends, so no real Timer is left pending.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'loading the tracking data shows skeleton placeholders, not a '
      'spinner or timeline content', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Never resolves on its own — keeps the tracking-data fetch
    // permanently in flight, so the screen stays in its loading state
    // for the assertions below.
    final pendingData = Completer<HttpClientRequest>();
    routing.dataResponder = (_) => pendingData.future;

    await tester.pumpWidget(_buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppSkeletonCard), findsNWidgets(4));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Order Placed'), findsNothing);
    expect(find.text('Order Tracking'), findsNothing);

    // Resolve the still-pending request, then let the now-loaded
    // timeline's staggered FadeInUp entrances finish (not just start)
    // and dispose the screen (cancels its 8s poll Timer), so no Timer
    // is left pending when the test ends.
    pendingData.complete(
      FakeHttpClientRequest(FakeHttpClientResponse(jsonEncode({
        'status': 'PENDING',
        'trackingCode': _trackingCode,
        'grandTotal': 10.0,
        'deliveryFee': 2.0,
      }))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'reduced motion renders the loaded status timeline without a '
      'FadeInUp ancestor', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    routing.dataResponder = (_) async => FakeHttpClientRequest(
          FakeHttpClientResponse(jsonEncode({
            'status': 'ACCEPTED',
            'trackingCode': _trackingCode,
            'grandTotal': 12.5,
            'deliveryFee': 2.0,
            'deliveryAddress': '123 Main St',
          })),
        );

    await tester.pumpWidget(
      _buildApp(
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Accepted'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Accepted'),
        matching: find.byType(FadeInUp),
      ),
      findsNothing,
    );
    expect(find.byType(FadeInUp), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
