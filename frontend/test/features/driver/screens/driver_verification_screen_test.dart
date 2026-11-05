import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/driver/screens/driver_verification_screen.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

const _imagePickerChannel = MethodChannel('plugins.flutter.io/image_picker');

void main() {
  setUpAll(() {
    // Every API call fired by the screen must fail immediately rather than
    // hang on a real network timeout — nothing here needs the backend up.
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://127.0.0.1:1');
  });

  setUp(() {
    // The camera is unavailable in tests, so the photo pick fails.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePickerChannel, (call) async {
      throw PlatformException(code: 'camera_unavailable');
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_imagePickerChannel, null);
    AppToast.debugReset();
  });

  testWidgets(
      'a failed document upload shows an AppToast error, not a SnackBar',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: DriverVerificationScreen()),
    );
    await tester.pump();

    // Vehicle step -> plate step, enter a plate, -> documents step.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'ABC123');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    // Take a photo for the first document; the pick fails and the screen
    // reports it.
    await tester.ensureVisible(find.text('Your Photo'));
    await tester.tap(find.text('Your Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pump();
  });
}
