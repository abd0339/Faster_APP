import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:faster_app/shared/widgets/app_button.dart';

void main() {
  group('AppOutlineButton disabled state', () {
    testWidgets(
        'passes a null onPressed to the underlying OutlinedButton when '
        'widget.onPressed is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppOutlineButton(
              label: 'Disabled',
              onPressed: null,
            ),
          ),
        ),
      );

      final outlinedButton =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(outlinedButton.onPressed, isNull);
    });

    testWidgets(
        'passes a non-null onPressed to the underlying OutlinedButton when '
        'widget.onPressed is set', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppOutlineButton(
              label: 'Enabled',
              onPressed: () {},
            ),
          ),
        ),
      );

      final outlinedButton =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(outlinedButton.onPressed, isNotNull);
    });
  });

  group('press-scale animation', () {
    testWidgets('AppButton scales down on press and back up on release',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Press me',
              onPressed: () {},
            ),
          ),
        ),
      );

      AnimatedScale animatedScale() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale));

      expect(animatedScale().scale, 1.0);

      final center = tester.getCenter(find.byType(AppButton));
      final gesture = await tester.startGesture(center);
      await tester.pumpAndSettle();

      expect(animatedScale().scale, 0.97);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(animatedScale().scale, 1.0);
    });

    testWidgets('AppOutlineButton scales down on press and back up on release',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppOutlineButton(
              label: 'Press me',
              onPressed: () {},
            ),
          ),
        ),
      );

      AnimatedScale animatedScale() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale));

      expect(animatedScale().scale, 1.0);

      final center = tester.getCenter(find.byType(AppOutlineButton));
      final gesture = await tester.startGesture(center);
      await tester.pumpAndSettle();

      expect(animatedScale().scale, 0.97);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(animatedScale().scale, 1.0);
    });

    testWidgets('AppButton scales back up when the gesture is cancelled',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Press me',
              onPressed: () {},
            ),
          ),
        ),
      );

      AnimatedScale animatedScale() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale));

      final center = tester.getCenter(find.byType(AppButton));
      final gesture = await tester.startGesture(center);
      await tester.pumpAndSettle();
      expect(animatedScale().scale, 0.97);

      // Dragging far away triggers onTapCancel for the GestureDetector.
      await gesture.moveBy(const Offset(500, 500));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(animatedScale().scale, 1.0);
    });
  });

  group('disabled styling', () {
    testWidgets('AppButton disabled background uses 40% alpha', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppButton(
              label: 'Disabled',
              onPressed: null,
              isLoading: false,
            ),
          ),
        ),
      );

      final outlinedButton =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final disabledColor =
          outlinedButton.style?.backgroundColor?.resolve({WidgetState.disabled});
      expect(disabledColor, isNotNull);
      // withValues(alpha: 0.4) on a fully opaque color -> alpha channel 102/255
      expect(disabledColor!.a, closeTo(0.4, 0.01));
    });

    testWidgets(
        'AppOutlineButton applies 40% opacity styling when onPressed is null',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppOutlineButton(
              label: 'Disabled',
              onPressed: null,
            ),
          ),
        ),
      );

      final outlinedButton =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final side =
          outlinedButton.style?.side?.resolve({WidgetState.disabled});
      final foreground = outlinedButton.style?.foregroundColor
          ?.resolve({WidgetState.disabled});

      expect(side, isNotNull);
      expect(side!.color.a, closeTo(0.4, 0.01));
      expect(foreground, isNotNull);
      expect(foreground!.a, closeTo(0.4, 0.01));
    });
  });
}
