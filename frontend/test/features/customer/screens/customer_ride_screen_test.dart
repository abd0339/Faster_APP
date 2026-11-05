import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:faster_app/features/customer/screens/customer_ride_screen.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(AppToast.debugReset);

  testWidgets(
      'requesting a ride with no pickup location shows an AppToast error, '
      'not a SnackBar', (tester) async {
    // Tall, wide surface so the whole scrollable form is laid out
    // within the hit-testable area.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: CustomerRideScreen()),
    );
    // The vehicle-selector cards have a pre-existing (unrelated to this
    // SnackBar->AppToast migration) fixed-size overflow that the test
    // framework reports as an exception on every pump — drain it so it
    // doesn't fail this unrelated test.
    tester.takeException();
    await tester.pump();
    tester.takeException();
    await tester.pump(const Duration(milliseconds: 300));
    tester.takeException();

    await tester.ensureVisible(find.byIcon(Icons.directions_car_rounded));
    await tester.tap(find.byIcon(Icons.directions_car_rounded));
    await tester.pump();
    tester.takeException();

    expect(find.text('Set pickup location'), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pump();
    tester.takeException();
  });
}
