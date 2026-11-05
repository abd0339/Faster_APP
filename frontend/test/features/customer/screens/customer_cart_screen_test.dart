import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/customer/models/cart_item.dart';
import 'package:faster_app/features/customer/screens/customer_cart_screen.dart';
import 'package:faster_app/features/customer/services/cart_service.dart';
import 'package:faster_app/shared/widgets/app_empty_state.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

void main() {
  setUpAll(() {
    // Any API call this screen fires in the background (quote fetch,
    // GPS reverse-geocode) must fail immediately rather than hang on a
    // real network timeout — nothing here needs the backend to be up.
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://127.0.0.1:1');
  });

  tearDown(() {
    AppToast.debugReset();
    CartService.instance.clear();
  });

  testWidgets(
      'placing an order with no delivery address shows an AppToast error, '
      'not a SnackBar', (tester) async {
    CartService.instance.clear();
    // The Place Order button only renders once the cart has items —
    // seed one so the button (and its validation) is reachable.
    CartService.instance.addItem(
      CartItem(itemId: 1, name: 'Burger', price: 5.0),
      42,
      'Test Merchant',
    );

    // Tall, wide surface so the whole scrollable form (including the
    // Place Order button) is laid out within the hit-testable area.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CustomerCartScreen())),
    );
    // Let the harmless initState location-detect/quote attempts settle
    // without waiting on their real (and here, unmocked) network calls.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.byIcon(Icons.check_rounded));
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pump();

    expect(find.text('Please enter your delivery address'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pump();
  });

  testWidgets(
      'an empty cart renders AppEmptyState with a working Browse stores '
      'action', (tester) async {
    CartService.instance.clear();

    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const CustomerCartScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    final emptyState = tester.widget<AppEmptyState>(find.byType(AppEmptyState));
    expect(emptyState.icon, Icons.shopping_cart_outlined);
    expect(emptyState.message, 'Your cart is empty');
    expect(find.text('Your cart is empty'), findsOneWidget);

    await tester.tap(find.text('Browse stores'));
    await tester.pumpAndSettle();

    // The action navigates back to the store/stores screen (pop) — the
    // cart screen's route is gone and nothing is left to find.
    expect(find.byType(CustomerCartScreen), findsNothing);
  });
}
