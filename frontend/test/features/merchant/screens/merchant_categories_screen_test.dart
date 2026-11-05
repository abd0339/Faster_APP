import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/features/merchant/screens/merchant_categories_screen.dart';
import 'package:faster_app/shared/widgets/app_toast.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  setUpAll(() {
    // Every API call fired by the screen must fail immediately rather than
    // hang on a real network timeout — nothing here needs the backend up.
    dotenv.testLoad(fileInput: 'BACKEND_URL=http://127.0.0.1:1');
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    AppToast.debugReset();
  });

  testWidgets(
      'a failed categories load shows an AppToast error, not a SnackBar, '
      'and the empty state renders the folder icon', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: MerchantCategoriesScreen()),
    );
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // Categories list stays empty after the failed load — the empty state
    // now shows a folder icon instead of the decorative 🗂️ emoji.
    expect(find.byIcon(Icons.folder_open_rounded), findsOneWidget);
    expect(find.text('🗂️'), findsNothing);

    await tester.pump(AppToast.displayDuration);
    await tester.pump();
  });
}
