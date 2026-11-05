import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:faster_app/core/constants/app_text_styles.dart';

void main() {
  // google_fonts touches the asset bundle (to check for bundled font
  // overrides) even when just building a TextStyle, so the test binding
  // must be initialized first — otherwise ServicesBinding.instance throws.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mirrors offline/first-launch conditions: disable google_fonts' runtime
  // HTTP fetch (the test harness returns HTTP 400 for every request anyway)
  // so we exercise exactly the fallback path a real device hits with no
  // connectivity. The call must still return a usable TextStyle and must
  // not throw.
  GoogleFonts.config.allowRuntimeFetching = false;

  // AppTextStyles.* fields are `static final`, so the first access to a
  // Poppins-based (or Open-Sans-based) field lazily calls GoogleFonts.*(),
  // which kicks off google_fonts' unawaited background fetch-and-register
  // step. With fetching disabled above, that step fails — and because the
  // call that triggers it is unawaited, the failure surfaces as an
  // asynchronous zone error that can land on whichever test happens to be
  // running when it fires, rather than on the test that caused it.
  // Warm up both font families once, up front, inside a guarded zone so
  // that expected failure is swallowed here instead of leaking into the
  // "font families, sizes and weights" tests below.
  setUpAll(() async {
    final warmUp = runZonedGuarded(() async {
      // Touch every AppTextStyles field once so google_fonts attempts (and
      // fails) the background fetch for every distinct family+weight
      // combination the 16 styles actually use, right here — instead of
      // during whichever test happens to first reference that field.
      // ignore: unused_local_variable
      final allStyles = <TextStyle>[
        AppTextStyles.displayLarge,
        AppTextStyles.displayMedium,
        AppTextStyles.headlineLarge,
        AppTextStyles.headlineMedium,
        AppTextStyles.headlineSmall,
        AppTextStyles.bodyLarge,
        AppTextStyles.bodyMedium,
        AppTextStyles.bodySmall,
        AppTextStyles.labelLarge,
        AppTextStyles.labelMedium,
        AppTextStyles.button,
        AppTextStyles.buttonOutline,
        AppTextStyles.price,
        AppTextStyles.priceSmall,
        AppTextStyles.caption,
      ];
      await pumpEventQueue();
    }, (error, stack) {
      // Expected: the simulated offline background fetch failing.
    });
    if (warmUp != null) await warmUp;
  });

  group('AppTextStyles font families, sizes and weights', () {
    test('displayLarge uses Poppins at 32/700', () {
      expect(AppTextStyles.displayLarge.fontSize, 32);
      expect(AppTextStyles.displayLarge.fontWeight, FontWeight.w700);
      expect(AppTextStyles.displayLarge.fontFamily, contains('Poppins'));
    });

    test('bodyLarge uses Open Sans at 16/400', () {
      expect(AppTextStyles.bodyLarge.fontSize, 16);
      expect(AppTextStyles.bodyLarge.fontWeight, FontWeight.w400);
      // google_fonts resolves the family to its internal asset key, which
      // has no space (e.g. "OpenSans_regular") — assert on that form.
      expect(AppTextStyles.bodyLarge.fontFamily, contains('OpenSans'));
    });

    test('button uses Poppins at 15/700', () {
      expect(AppTextStyles.button.fontSize, 15);
      expect(AppTextStyles.button.fontWeight, FontWeight.w700);
      expect(AppTextStyles.button.fontFamily, contains('Poppins'));
    });

    test('caption uses Open Sans at 12/400 (accessibility floor)', () {
      expect(AppTextStyles.caption.fontSize, 12);
      expect(AppTextStyles.caption.fontWeight, FontWeight.w400);
      expect(AppTextStyles.caption.fontFamily, contains('OpenSans'));
    });
  });

  group('google_fonts offline-first-launch safety', () {
    // With runtime fetching disabled (set above) and no bundled Poppins/Open
    // Sans asset, google_fonts' background fetch-and-register step is
    // guaranteed to fail — exactly like a real device with no connectivity
    // on first launch. The call itself must still hand back a usable
    // TextStyle synchronously and must never throw to the caller; any error
    // from the unawaited background step is captured here (inside this
    // test's own zone) purely so it doesn't leak into a later test.
    test('GoogleFonts.poppins() returns a non-null TextStyle synchronously '
        'without throwing, even when the background font fetch fails', () async {
      TextStyle? style;
      await runZonedGuarded(() async {
        expect(() => style = GoogleFonts.poppins(), returnsNormally);
        await pumpEventQueue();
      }, (error, stack) {
        // Expected: the simulated offline background fetch failing.
      });
      expect(style, isA<TextStyle>());
    });

    test('GoogleFonts.openSans() returns a non-null TextStyle synchronously '
        'without throwing, even when the background font fetch fails', () async {
      TextStyle? style;
      await runZonedGuarded(() async {
        expect(() => style = GoogleFonts.openSans(), returnsNormally);
        await pumpEventQueue();
      }, (error, stack) {
        // Expected: the simulated offline background fetch failing.
      });
      expect(style, isA<TextStyle>());
    });
  });
}
