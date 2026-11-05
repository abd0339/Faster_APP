import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/core/constants/api_constants.dart';
import 'package:faster_app/features/driver/screens/driver_dashboard_screen.dart';
import 'package:faster_app/shared/widgets/app_empty_state.dart';
import 'package:faster_app/shared/widgets/app_error_state.dart';
import 'package:faster_app/shared/widgets/app_skeleton_card.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

import '../../../helpers/fake_http.dart';

const _geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Routes requests by path so the dashboard's own order-list fetch
/// (`/api/orders/driver`) can be driven per-test. `/api/ledger/my/debt` and
/// `/api/driver/status` always succeed quietly with an empty object — they
/// aren't under test here and a failure would otherwise race with (and
/// sometimes swallow) the order-list assignment, since both are awaited
/// together via `Future.wait`. Every other endpoint (going online/offline,
/// location pings) fails immediately, matching this screen's pre-existing
/// "backend unreachable" test below.
class _OrdersRouting {
  Future<HttpClientRequest> Function(Uri url)? ordersResponder;

  Future<HttpClientRequest> route(Uri url) {
    if (url.path == ApiConstants.driverOrders) {
      if (ordersResponder != null) return ordersResponder!(url);
      return Future.value(
        FakeHttpClientRequest(FakeHttpClientResponse('[]')),
      );
    }
    if (url.path == ApiConstants.myDebt || url.path == ApiConstants.driverStatus) {
      return Future.value(
        FakeHttpClientRequest(FakeHttpClientResponse('{}')),
      );
    }
    return Future.error(const SocketException('Connection refused'));
  }
}

final _singleOrderJson = jsonEncode([
  {
    'id': 1,
    'trackingCode': 'ORD001',
    'status': 'DELIVERED',
    'grandTotal': 12.5,
    'deliveryAddress': '123 Main St',
    'orderType': 'LOGISTICS',
  },
]);

Widget _buildApp({MediaQueryData? mediaQueryData}) {
  const app = MaterialApp(home: DriverDashboardScreen());
  if (mediaQueryData == null) return app;
  return MediaQuery(data: mediaQueryData, child: app);
}

void main() {
  final routing = _OrdersRouting();

  setUpAll(() {
    // Every unrouted API call fired by the screen must fail immediately
    // rather than hang on a real network timeout — nothing here needs the
    // backend up.
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://localhost:8080');
    // Installed once, globally: see RoutingHttpClient's doc comment for
    // why a per-test HttpOverrides.runZoned wrapper wouldn't work here.
    HttpOverrides.global = TestHttpOverrides(RoutingHttpClient(routing.route));
  });

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Location permission is denied, so going online proceeds without GPS.
    messenger.setMockMethodCallHandler(_geolocatorChannel, (call) async => 1);
    // No stored session token.
    messenger.setMockMethodCallHandler(
        _secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_geolocatorChannel, null);
    messenger.setMockMethodCallHandler(_secureStorageChannel, null);
    AppToast.debugReset();
    routing.ordersResponder = null;
  });

  testWidgets(
      'going online when the backend rejects it shows an AppToast error, '
      'not a SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    routing.ordersResponder = (_) async =>
        FakeHttpClientRequest(FakeHttpClientResponse('[]'));

    await tester.pumpWidget(_buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The empty "No rides yet" state renders the AppEmptyState icon.
    expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);

    await tester.ensureVisible(find.textContaining('Go Online'));
    await tester.tap(find.textContaining('Go Online'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pump();
  });

  testWidgets(
      'loading the recent-orders list shows skeleton placeholders, not a '
      'spinner or order content', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Never resolves on its own — keeps the order-list fetch permanently
    // in flight, so the screen stays in its loading state for the
    // assertions below.
    final pendingOrders = Completer<HttpClientRequest>();
    routing.ordersResponder = (_) => pendingOrders.future;

    await tester.pumpWidget(_buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppSkeletonCard), findsNWidgets(4));
    // The one remaining CircularProgressIndicator is the "Commission Due"
    // gauge, which is unrelated to order loading and always rendered — the
    // bare spinner that used to stand in for the order list is gone.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AppEmptyState), findsNothing);

    // Resolve the still-pending request so its own Dio request timer is
    // cancelled before the test tears down the widget tree.
    pendingOrders.complete(
      FakeHttpClientRequest(FakeHttpClientResponse('[]')),
    );
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('an empty order list shows AppEmptyState with "No rides yet"',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    routing.ordersResponder = (_) async =>
        FakeHttpClientRequest(FakeHttpClientResponse('[]'));

    await tester.pumpWidget(_buildApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No rides yet'), findsOneWidget);
    expect(find.byType(AppSkeletonCard), findsNothing);
  });

  testWidgets(
      'reduced motion renders a non-empty recent-orders list without a '
      'FadeInUp ancestor', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final orderJson = jsonEncode([
      {
        'id': 1,
        'trackingCode': 'ORD001',
        'status': 'DELIVERED',
        'grandTotal': 12.5,
        'deliveryAddress': '123 Main St',
        'orderType': 'LOGISTICS',
      },
      {
        'id': 2,
        'trackingCode': 'ORD002',
        'status': 'DELIVERED',
        'grandTotal': 8.0,
        'deliveryAddress': '456 Oak Ave',
        'orderType': 'LOGISTICS',
      },
    ]);
    routing.ordersResponder = (_) async =>
        FakeHttpClientRequest(FakeHttpClientResponse(orderJson));

    await tester.pumpWidget(
      _buildApp(
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ORD001'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('ORD001'),
        matching: find.byType(FadeInUp),
      ),
      findsNothing,
    );
    expect(find.byType(FadeInUp), findsNothing);
  });
  testWidgets(
      'a failed order-list load shows AppErrorState, and Retry reloads the '
      'list', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    routing.ordersResponder =
        (_) => Future.error(const SocketException('Connection refused'));

    await tester.pumpWidget(
      _buildApp(
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text("Couldn't load orders"), findsOneWidget);
    expect(find.byType(AppEmptyState), findsNothing);

    routing.ordersResponder = (_) async =>
        FakeHttpClientRequest(FakeHttpClientResponse(_singleOrderJson));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppErrorState), findsNothing);
    expect(find.text('ORD001'), findsOneWidget);
  });

  testWidgets(
      'refreshing an already-populated order list keeps the recent orders '
      'on screen instead of swapping them for skeletons', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    routing.ordersResponder = (_) async =>
        FakeHttpClientRequest(FakeHttpClientResponse(_singleOrderJson));

    await tester.pumpWidget(
      _buildApp(
        mediaQueryData: const MediaQueryData(disableAnimations: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ORD001'), findsOneWidget);

    // Start a refresh from the Orders tab and keep it in flight, then come
    // back to the recent-orders list on the Home tab.
    final pendingOrders = Completer<HttpClientRequest>();
    routing.ordersResponder = (_) => pendingOrders.future;
    await tester.tap(find.text('Orders'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();
    await tester.tap(find.text('Home'));
    await tester.pump();

    expect(find.text('ORD001'), findsOneWidget);
    expect(find.byType(AppSkeletonCard), findsNothing);

    pendingOrders.complete(
      FakeHttpClientRequest(FakeHttpClientResponse(_singleOrderJson)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  });
}
