import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/core/constants/api_constants.dart';
import 'package:faster_app/core/services/websocket_service.dart';
import 'package:faster_app/features/customer/screens/customer_order_tracking_screen.dart';
import 'package:faster_app/shared/widgets/app_skeleton_card.dart';
import 'package:faster_app/shared/widgets/status_badge.dart';

import '../../../helpers/fake_http.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _testOrderId = 42;

/// Routes requests by path so the screen's own order fetch
/// (`/api/orders/42`) can be driven per-test. Everything else (the
/// WebSocket's SockJS handshake going out over plain HTTP) fails
/// immediately — nothing here needs a live backend or broker.
class _OrderRouting {
  Future<HttpClientRequest> Function(Uri url)? orderResponder;

  Future<HttpClientRequest> route(Uri url) {
    if (url.path == '${ApiConstants.orders}/$_testOrderId') {
      if (orderResponder != null) return orderResponder!(url);
      return Future.value(
        FakeHttpClientRequest(FakeHttpClientResponse('{}')),
      );
    }
    return Future.error(const SocketException('Connection refused'));
  }
}

Widget _buildApp({MediaQueryData? mediaQueryData}) {
  const app = MaterialApp(
    home: CustomerOrderTrackingScreen(
      orderId: _testOrderId,
      trackingCode: 'TRK42',
    ),
  );
  if (mediaQueryData == null) return app;
  return MediaQuery(data: mediaQueryData, child: app);
}

void main() {
  final routing = _OrderRouting();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://localhost:8080');
    HttpOverrides.global = TestHttpOverrides(RoutingHttpClient(routing.route));
  });

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // No stored session token.
    messenger.setMockMethodCallHandler(
        _secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorageChannel, null);
    routing.orderResponder = null;
  });

  // The screen's WebSocket subscription never disconnects on its own (the
  // app-wide socket is meant to outlive one screen), and the connection
  // attempt's failed-socket retry schedules a real Timer. It has to be
  // cancelled from inside the test body itself — a package:test tearDown()
  // runs too late, after flutter_test's own pending-timer check already
  // ran and failed.
  void disconnectWebSocket() => WebSocketService.instance.disconnect();

  testWidgets(
      'loading the order shows skeleton placeholders, not a spinner or '
      'timeline content', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Never resolves on its own — keeps the order fetch permanently in
    // flight, so the screen stays in its loading state for the
    // assertions below.
    final pendingOrder = Completer<HttpClientRequest>();
    routing.orderResponder = (_) => pendingOrder.future;

    await tester.pumpWidget(_buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppSkeletonCard), findsNWidgets(4));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(StatusBadge), findsNothing);
    expect(find.text('Current status'), findsNothing);

    // Resolve the still-pending request so its own Dio request timer is
    // cancelled before the test tears down the widget tree.
    pendingOrder.complete(
      FakeHttpClientRequest(FakeHttpClientResponse(jsonEncode({
        'status': 'PENDING',
        'grandTotal': 10.0,
      }))),
    );
    // Let the now-loaded timeline's staggered FadeInUp entrances finish
    // (not just start) before the test ends, so none of their internal
    // Timers are still pending when the widget tree is disposed.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    disconnectWebSocket();
  });

  testWidgets(
      'reduced motion renders the loaded status timeline without a '
      'FadeInUp ancestor', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    routing.orderResponder = (_) async => FakeHttpClientRequest(
          FakeHttpClientResponse(jsonEncode({
            'status': 'ACCEPTED',
            'grandTotal': 12.5,
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

    // "Current status" only decorates the active timeline step, so it's
    // an unambiguous anchor into the progress-steps card (unlike the
    // step label text, which is duplicated by the status-hero title).
    expect(find.text('Current status'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Current status'),
        matching: find.byType(FadeInUp),
      ),
      findsNothing,
    );
    expect(find.byType(FadeInUp), findsNothing);
    disconnectWebSocket();
  });
}
