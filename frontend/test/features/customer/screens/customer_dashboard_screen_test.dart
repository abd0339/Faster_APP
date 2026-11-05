import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/auth/bloc/auth_bloc.dart';
import 'package:faster_app/features/customer/screens/customer_dashboard_screen.dart';
import 'package:faster_app/shared/widgets/app_empty_state.dart';
import 'package:faster_app/shared/widgets/app_error_state.dart';
import 'package:faster_app/shared/widgets/app_skeleton_card.dart';
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

/// Routes every request by path so the dashboard's own order-list fetch
/// (`/api/orders/customer`) can be driven per-test while every other
/// request — chiefly the Browse tab's store list, which this screen loads
/// eagerly alongside the Orders tab via its `IndexedStack` — gets a quiet
/// empty-list success instead of an error toast that could interfere with
/// these tests.
class _OrdersRouting {
  Future<HttpClientRequest> Function(Uri url)? ordersResponder;

  Future<HttpClientRequest> route(Uri url) {
    if (url.path == '/api/orders/customer' && ordersResponder != null) {
      return ordersResponder!(url);
    }
    return Future.value(
      FakeHttpClientRequest(FakeHttpClientResponse('[]')),
    );
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
  final app = MaterialApp(
    home: BlocProvider<AuthBloc>(
      create: (_) => AuthBloc(),
      child: const CustomerDashboardScreen(),
    ),
  );
  if (mediaQueryData == null) return app;
  return MediaQuery(data: mediaQueryData, child: app);
}

void main() {
  final routing = _OrdersRouting();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://localhost:8080');
    // StorageService reads the auth token via flutter_secure_storage on
    // every request — no platform channel exists in widget tests, so give
    // it a working fake instead.
    FlutterSecureStoragePlatform.instance = _FakeSecureStorage();
    // Installed once, globally: see RoutingHttpClient's doc comment for
    // why a per-test HttpOverrides.runZoned wrapper wouldn't work here.
    HttpOverrides.global = TestHttpOverrides(RoutingHttpClient(routing.route));
  });

  tearDown(() {
    AppToast.debugReset();
    routing.ordersResponder = null;
  });

  testWidgets(
      'placing a direct-delivery order with no pickup location shows an '
      'AppToast error, not a SnackBar', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<AuthBloc>(
          create: (_) => AuthBloc(),
          child: const CustomerDashboardScreen(),
        ),
      ),
    );
    await tester.pump();

    // Open the "New Order" sheet from the FAB, then pick Direct Delivery.
    await tester.tap(find.text('New Order'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Direct Delivery Order'));
    await tester.pump();
    await tester.tap(find.text('Direct Delivery Order'));
    // The Direct Delivery sheet embeds GooglePlacesSearchField, which has
    // a pre-existing (unrelated to this SnackBar->AppToast migration)
    // overflow — drain it on every pump instead of pumpAndSettle (which
    // would otherwise surface it as a test failure).
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      tester.takeException();
    }

    // Pickup is left empty — tap Place Order straight away.
    await tester.ensureVisible(find.text('Place Order'));
    await tester.tap(find.text('Place Order'));
    await tester.pump();
    tester.takeException();

    expect(find.text('Set pickup location'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pump();
    tester.takeException();
  });

  testWidgets(
      'loading the order list shows skeleton placeholders, not a spinner '
      'or order content', (tester) async {
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
    // Let the Browse tab's own store-list fetch (already resolved by the
    // routing client's default response) fully settle so its internal
    // Dio request timer doesn't linger past this test.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Orders'));
    await tester.pump();

    expect(find.byType(AppSkeletonCard), findsNWidgets(4));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AppEmptyState), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);

    // Resolve the still-pending request so its own Dio request timer is
    // cancelled before the test tears down the widget tree.
    pendingOrders.complete(
      FakeHttpClientRequest(FakeHttpClientResponse('[]')),
    );
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('an empty order list shows AppEmptyState with "No orders yet"',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    routing.ordersResponder = (_) async =>
        FakeHttpClientRequest(FakeHttpClientResponse('[]'));

    await tester.pumpWidget(_buildApp());
    await tester.pump();

    await tester.tap(find.text('Orders'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No orders yet'), findsOneWidget);
    expect(find.byType(AppSkeletonCard), findsNothing);
  });

  testWidgets(
      'reduced motion renders a non-empty order list without a FadeInUp '
      'ancestor', (tester) async {
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

    await tester.tap(find.text('Orders'));
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

    await tester.tap(find.text('Orders'));
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
      'refreshing an already-populated order list keeps the orders on '
      'screen instead of swapping them for skeletons', (tester) async {
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

    await tester.tap(find.text('Orders'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('ORD001'), findsOneWidget);

    // Keep the refresh in flight for the assertions below.
    final pendingOrders = Completer<HttpClientRequest>();
    routing.ordersResponder = (_) => pendingOrders.future;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();

    expect(find.text('ORD001'), findsOneWidget);
    expect(find.byType(AppSkeletonCard), findsNothing);

    pendingOrders.complete(
      FakeHttpClientRequest(FakeHttpClientResponse(_singleOrderJson)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  });
}
