import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/core/constants/app_motion.dart';

void main() {
  test('AppMotion duration and curve values', () {
    expect(AppMotion.microDuration, const Duration(milliseconds: 150));
    expect(AppMotion.microCurve, Curves.easeOut);

    expect(AppMotion.transitionDuration, const Duration(milliseconds: 250));
    expect(AppMotion.transitionCurve, Curves.easeInOut);

    expect(AppMotion.listEntranceDuration, const Duration(milliseconds: 300));
    expect(AppMotion.listStaggerDelay, const Duration(milliseconds: 40));
  });

  group('AppMotion.reduceMotion', () {
    testWidgets('returns true when MediaQuery.disableAnimations is true',
        (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(AppMotion.reduceMotion(capturedContext), isTrue);
    });

    testWidgets('returns false when MediaQuery.disableAnimations is false',
        (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(AppMotion.reduceMotion(capturedContext), isFalse);
    });
  });
}
